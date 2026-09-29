
#include <Arduino.h>
#include <Wire.h>
#include <string.h>
#include "driver/spi_slave.h"
#include "esp_err.h"

// =====================================================
// ESP32 DOIT DEVKIT V1 PIN CONFIGURATION
// =====================================================

// SPI: FPGA = Master, ESP32 = Slave
#define FPGA_TX_REQ 25
#define SPI_MOSI    23
#define SPI_MISO    19
#define SPI_SCLK    18
#define SPI_CS       5

// I2C: ESP32 = Master, FPGA = Slave
#define I2C_SDA     21
#define I2C_SCL     22
#define FPGA_I2C_ADDR 0x50

#define SPI_HOST_USED VSPI_HOST
#define SPI_TIMEOUT_MS 1000

// Packet expected by the FPGA packet parser:
// CMD, I2C address, register, length, data
uint8_t packet[7] = {
  0x01, 0x50, 0x20, 0x03, 0xA5, 0xB6, 0xC7
};

bool spi_ready = false;
bool i2c_ready = false;

// =====================================================
// SPI SLAVE INITIALIZATION
// =====================================================
bool initializeSPI()
{
  pinMode(FPGA_TX_REQ, OUTPUT);
  digitalWrite(FPGA_TX_REQ, LOW);

  spi_bus_config_t buscfg = {};
  buscfg.mosi_io_num = SPI_MOSI;
  buscfg.miso_io_num = SPI_MISO;
  buscfg.sclk_io_num = SPI_SCLK;
  buscfg.quadwp_io_num = -1;
  buscfg.quadhd_io_num = -1;
  buscfg.max_transfer_sz = 8;

  spi_slave_interface_config_t slvcfg = {};
  slvcfg.spics_io_num = SPI_CS;
  slvcfg.flags = 0;
  slvcfg.queue_size = 1;
  slvcfg.mode = 0;

  esp_err_t err = spi_slave_initialize(
    SPI_HOST_USED,
    &buscfg,
    &slvcfg,
    SPI_DMA_DISABLED
  );

  if (err != ESP_OK) {
    Serial.printf(
      "SPI initialization failed: %s\n",
      esp_err_to_name(err)
    );
    return false;
  }

  Serial.println("PASS: ESP32 SPI slave initialized");
  return true;
}

// =====================================================
// SEND ONE BYTE TO FPGA OVER SPI MISO
// FPGA generates SCLK and CS_N.
// =====================================================
bool sendSPIByte(uint8_t txByte, uint8_t *receivedByte)
{
  uint8_t tx_buf[1] = { txByte };
  uint8_t rx_buf[1] = { 0x00 };

  spi_slave_transaction_t trans = {};
  trans.length = 8;
  trans.tx_buffer = tx_buf;
  trans.rx_buffer = rx_buf;

  // Queue the ESP32 slave response before requesting FPGA transfer.
  esp_err_t err = spi_slave_queue_trans(
    SPI_HOST_USED,
    &trans,
    pdMS_TO_TICKS(SPI_TIMEOUT_MS)
  );

  if (err != ESP_OK) {
    Serial.printf("SPI queue failed: %s\n", esp_err_to_name(err));
    return false;
  }

  // Pulse request: FPGA SPI master should start one byte transfer.
  digitalWrite(FPGA_TX_REQ, HIGH);
  delayMicroseconds(10);
  digitalWrite(FPGA_TX_REQ, LOW);

  spi_slave_transaction_t *completed = nullptr;

  err = spi_slave_get_trans_result(
    SPI_HOST_USED,
    &completed,
    pdMS_TO_TICKS(SPI_TIMEOUT_MS)
  );

  if (err != ESP_OK || completed == nullptr) {
    Serial.printf(
      "SPI transaction timeout/error: %s\n",
      esp_err_to_name(err)
    );
    return false;
  }

  *receivedByte = rx_buf[0];

  // Give the FPGA master time to return to IDLE before next request.
  delayMicroseconds(100);

  return true;
}

// =====================================================
// I2C READBACK FROM FPGA REGISTER 0x20
// =====================================================
bool readFPGARegisters(uint8_t startRegister,
                       uint8_t *data,
                       uint8_t length)
{
  Wire.beginTransmission(FPGA_I2C_ADDR);
  Wire.write(startRegister);

  // Keep the bus active for the repeated START.
  uint8_t err = Wire.endTransmission(false);

  if (err != 0) {
    Serial.printf(
      "I2C register pointer failed; error=%u\n", err
    );
    return false;
  }

  uint8_t count = Wire.requestFrom(
    (uint8_t)FPGA_I2C_ADDR,
    length,
    (uint8_t)true
  );

  if (count != length) {
    Serial.printf(
      "I2C read length mismatch: expected %u, received %u\n",
      length, count
    );

    while (Wire.available()) {
      Wire.read();
    }
    return false;
  }

  for (uint8_t i = 0; i < length; i++) {
    if (!Wire.available()) {
      Serial.println("I2C receive buffer ended unexpectedly");
      return false;
    }
    data[i] = Wire.read();
  }

  return true;
}

// =====================================================
// SETUP
// =====================================================
void setup()
{
  Serial.begin(115200);
  delay(1500);

  Serial.println();
  Serial.println("========================================");
  Serial.println(" SPI-TO-I2C END-TO-END INTEGRATION TEST");
  Serial.println("========================================");

  spi_ready = initializeSPI();

  Wire.begin(I2C_SDA, I2C_SCL);
  Wire.setClock(100000);

  // Check that the FPGA acknowledges the I2C address.
  Wire.beginTransmission(FPGA_I2C_ADDR);
  uint8_t err = Wire.endTransmission();

  if (err == 0) {
    i2c_ready = true;
    Serial.println("PASS: FPGA acknowledged I2C address 0x50");
  } else {
    Serial.printf("I2C address check failed: error %u\n", err);
  }

  if (!spi_ready) {
    Serial.println("SPI unavailable; test will not run.");
  }

  if (!i2c_ready) {
    Serial.println("I2C unavailable; check wiring and pull-ups.");
  }
}

// =====================================================
// MAIN TEST
// =====================================================
void loop()
{
  if (!spi_ready || !i2c_ready) {
    delay(2000);
    return;
  }

  Serial.println();
  Serial.println("----------------------------------------");
  Serial.println("STEP 1: Sending packet to FPGA over SPI");
  Serial.println("----------------------------------------");

  bool spi_ok = true;

  for (uint8_t i = 0; i < sizeof(packet); i++) {
    uint8_t received = 0x00;

    Serial.printf(
      "SPI byte %u/%u: sending 0x%02X ... ",
      i + 1, (unsigned)sizeof(packet), packet[i]
    );

    if (!sendSPIByte(packet[i], &received)) {
      Serial.println("FAILED");
      spi_ok = false;
      break;
    }

    Serial.printf("FPGA MOSI received by ESP32: 0x%02X\n",
                  received);
  }

  if (!spi_ok) {
    Serial.println("SPI packet transfer failed.");
    Serial.println("Check FPGA host_tx_req handling and SPI FSM.");
    delay(4000);
    return;
  }

  Serial.println("PASS: All seven SPI byte transactions completed");

  // Allow FPGA FIFO/parser/register logic to process the packet.
  Serial.println();
  Serial.println("STEP 2: Waiting for FPGA packet processing...");
  delay(50);

  Serial.println();
  Serial.println("STEP 3: Reading FPGA registers over I2C");

  uint8_t readback[3] = {0, 0, 0};

  if (!readFPGARegisters(0x20, readback, 3)) {
    Serial.println("FAIL: Could not read FPGA registers.");
    delay(4000);
    return;
  }

  Serial.printf(
    "FPGA register 0x20: 0x%02X\n", readback[0]
  );
  Serial.printf(
    "FPGA register 0x21: 0x%02X\n", readback[1]
  );
  Serial.printf(
    "FPGA register 0x22: 0x%02X\n", readback[2]
  );

  Serial.println();
  Serial.println("========================================");

  if (readback[0] == 0xA5 &&
      readback[1] == 0xB6 &&
      readback[2] == 0xC7) {
    Serial.println("END-TO-END TEST: PASS");
    Serial.println("All three data bytes match.");
  } else {
    Serial.println("END-TO-END TEST: FAIL");
    Serial.println("Readback does not match the transmitted data.");
    Serial.println("Check FPGA SPI receive, FIFO, parser, and I2C register map.");
  }

  Serial.println("========================================");

  // One test cycle every four seconds.
  delay(4000);
}