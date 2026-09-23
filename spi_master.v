module spi_master #(
    parameter CPOL = 0,
    parameter CPHA = 0
)(
    input  wire       clk_spi,
    input  wire       rst_n,
    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output reg        tx_ready,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        busy,
    output reg        spi_mosi,
    input  wire       spi_miso,
    output reg        spi_sclk,
    output reg        spi_cs_n
);
    localparam [1:0] IDLE     = 2'd0,
                     TRANSFER = 2'd1,
                     DONE     = 2'd2;
    reg [1:0] state;
    
    reg [2:0] bit_cnt;
    reg [7:0] shift_tx, shift_rx;
    reg       sclk_en;

    always @(posedge clk_spi or negedge rst_n) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx_ready <= 1'b1;
            rx_valid <= 1'b0;
            rx_data  <= 8'h00;
            busy     <= 1'b0;
            spi_mosi <= 1'b0;
            spi_cs_n <= 1'b1;
            spi_sclk <= CPOL;
            bit_cnt  <= 3'd7;
            sclk_en  <= 1'b0;
            shift_rx <= 8'h00;
            shift_tx <= 8'h00;
        end else begin
            rx_valid <= 1'b0;
            
            case (state)
                IDLE: begin
                    spi_cs_n <= 1'b1;
                    spi_sclk <= CPOL;
                    sclk_en  <= 1'b0;
                    if (tx_valid) begin
                        shift_tx <= tx_data;
                        spi_cs_n <= 1'b0;
                        tx_ready <= 1'b0;
                        busy     <= 1'b1;
                        bit_cnt  <= 3'd7;
                        state    <= TRANSFER;
                        spi_mosi <= tx_data[7];
                    end else begin
                        tx_ready <= 1'b1;
                        busy     <= 1'b0;
                    end
                end
                
                TRANSFER: begin
                    sclk_en <= ~sclk_en;
                    if (!sclk_en) begin
                        spi_sclk <= ~CPOL;
                        shift_rx <= {shift_rx[6:0], spi_miso};
                    end else begin
                        spi_sclk <= CPOL;
                        if (bit_cnt == 0) begin
                            state <= DONE;
                        end else begin
                            bit_cnt  <= bit_cnt - 1'b1;
                            shift_tx <= {shift_tx[6:0], 1'b0};
                            spi_mosi <= shift_tx[6];
                        end
                    end
                end
                
                DONE: begin
                    rx_data  <= shift_rx;
                    rx_valid <= 1'b1;
                    spi_cs_n <= 1'b1;
                    state    <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule