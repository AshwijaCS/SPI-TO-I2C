module i2c_slave #(
    parameter SLAVE_ADDR = 7'h50,
    parameter MAX_DATA_BYTES = 16
)(
    input  wire       clk_sys,
    input  wire       rst_n,
    
    inout  wire       i2c_sda,
    inout  wire       i2c_scl,
    
    input  wire [7:0] reg_addr,
    input  wire       reg_wr_en,
    input  wire       reg_rd_en,
    input  wire [7:0] wr_data,
    output reg  [7:0] rd_data,
    
    output wire       slave_busy,
    output reg        ack_error
);
    wire sda_in = (i2c_sda === 1'b0) ? 1'b0 : 1'b1;
    wire scl_in = (i2c_scl === 1'b0) ? 1'b0 : 1'b1;
    
    reg sda_oe, scl_oe;
    assign i2c_sda = sda_oe ? 1'b0 : 1'bz;
    assign i2c_scl = scl_oe ? 1'b0 : 1'bz;

    reg [2:0] scl_sync, sda_sync;
    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            scl_sync <= 3'b111;
            sda_sync <= 3'b111;
        end else begin
            scl_sync <= {scl_sync[1:0], scl_in};
            sda_sync <= {sda_sync[1:0], sda_in};
        end
    end

    wire scl_rise = (scl_sync[2:1] == 2'b01);
    wire scl_fall = (scl_sync[2:1] == 2'b10);
    wire sda_rise = (sda_sync[2:1] == 2'b01);
    wire sda_fall = (sda_sync[2:1] == 2'b10);
    wire scl_high = (scl_sync[1] == 1'b1);
    wire start_cond = scl_high && sda_fall;
    wire stop_cond  = scl_high && sda_rise;

    reg [7:0] reg_ctrl_stat, reg_i2c_addr, reg_wr_data, reg_rd_data, reg_length, reg_config;
    reg [7:0] data_buffer [0:MAX_DATA_BYTES-1];
    reg [7:0] active_ptr;
    
    wire [7:0] current_read_data;
    assign current_read_data = 
        (active_ptr == 8'h00) ? reg_ctrl_stat :
        (active_ptr == 8'h04) ? reg_i2c_addr :
        (active_ptr == 8'h08) ? reg_wr_data :
        (active_ptr == 8'h0C) ? reg_rd_data :
        (active_ptr == 8'h10) ? reg_length :
        (active_ptr == 8'h14) ? reg_config :
        (active_ptr >= 8'h20 && active_ptr < 8'h20+MAX_DATA_BYTES) ? data_buffer[active_ptr - 8'h20] :
        8'h00;
    
    localparam [3:0] IDLE       = 4'd0,
                     START_WAIT = 4'd1, 
                     RX_ADDR    = 4'd2,
                     ACK_ADDR   = 4'd3,
                     RX_REG     = 4'd4,
                     ACK_REG    = 4'd5,
                     RX_DATA    = 4'd6,
                     ACK_DATA   = 4'd7,
                     TX_DATA    = 4'd8,
                     WAIT_ACK   = 4'd9,
                     PREP_TX    = 4'd10;
    reg [3:0] state;
    
    reg [2:0] bit_cnt;
    reg [7:0] shift_reg, tx_shift;
    reg rw_bit;
    reg stretch_req;
    reg master_ack; // Added to capture ACK correctly on rising edge
    
    integer i;

    assign slave_busy = (state != IDLE) || stretch_req;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            sda_oe <= 0; scl_oe <= 0; ack_error <= 0; rd_data <= 0; stretch_req <= 0;
            reg_ctrl_stat <= 0; reg_i2c_addr <= 0; reg_wr_data <= 0; 
            reg_rd_data <= 0; reg_length <= 0; reg_config <= 0; master_ack <= 1'b1;
            for(i=0; i<MAX_DATA_BYTES; i=i+1) begin
                data_buffer[i] <= 0;
            end
        end else begin
            ack_error <= 1'b0;
            scl_oe <= stretch_req; 
            
            if (!slave_busy) begin
                if (reg_wr_en) begin
                    case (reg_addr)
                        8'h00: reg_ctrl_stat <= wr_data;
                        8'h04: reg_i2c_addr  <= wr_data;
                        8'h08: reg_wr_data   <= wr_data;
                        8'h0C: reg_rd_data   <= wr_data;
                        8'h10: reg_length    <= wr_data;
                        8'h14: reg_config    <= wr_data;
                        default: if (reg_addr >= 8'h20 && reg_addr < 8'h20+MAX_DATA_BYTES) 
                                    data_buffer[reg_addr - 8'h20] <= wr_data;
                    endcase
                end
                if (reg_rd_en) begin
                    case (reg_addr)
                        8'h00: rd_data <= reg_ctrl_stat;
                        8'h04: rd_data <= reg_i2c_addr;
                        8'h08: rd_data <= reg_wr_data;
                        8'h0C: rd_data <= reg_rd_data;
                        8'h10: rd_data <= reg_length;
                        8'h14: rd_data <= reg_config;
                        default: if (reg_addr >= 8'h20 && reg_addr < 8'h20+MAX_DATA_BYTES) 
                                    rd_data <= data_buffer[reg_addr - 8'h20];
                                 else rd_data <= 8'h00;
                    endcase
                end
            end

            if (start_cond) begin
                state <= START_WAIT; 
                sda_oe <= 0; stretch_req <= 0;
            end else if (stop_cond) begin
                state <= IDLE;
                sda_oe <= 0; stretch_req <= 0;
            end else begin
                if (state == PREP_TX) begin
                    tx_shift <= current_read_data;
                    sda_oe <= ~current_read_data[7];
                    state <= TX_DATA;
                    stretch_req <= 1'b0;
                end
                else if (scl_rise) begin
                    if (state == RX_ADDR || state == RX_REG || state == RX_DATA)
                        shift_reg <= {shift_reg[6:0], sda_sync[1]};
                    else if (state == WAIT_ACK)
                        master_ack <= sda_sync[1]; // FIX: Sample Master ACK securely during SCL HIGH
                end
                else if (scl_fall) begin
                    case (state)
                        IDLE: begin sda_oe <= 0; stretch_req <= 0; end
                        
                        START_WAIT: begin
                            state <= RX_ADDR;
                            bit_cnt <= 7;
                        end
                        
                        RX_ADDR: begin
                            if (bit_cnt == 0) begin
                                if (shift_reg[7:1] == SLAVE_ADDR) begin
                                    state <= ACK_ADDR;
                                    rw_bit <= shift_reg[0];
                                    sda_oe <= 1'b1; 
                                end else begin
                                    state <= IDLE; 
                                end
                            end else bit_cnt <= bit_cnt - 1'b1;
                        end
                        
                        ACK_ADDR: begin
                            sda_oe <= 0;
                            if (!rw_bit) begin
                                state <= RX_REG; bit_cnt <= 7;
                            end else begin
                                state <= PREP_TX; bit_cnt <= 7; stretch_req <= 1'b1; 
                            end
                        end
                        
                        RX_REG: begin
                            if (bit_cnt == 0) begin
                                active_ptr <= shift_reg;
                                state <= ACK_REG; sda_oe <= 1'b1;
                            end else bit_cnt <= bit_cnt - 1'b1;
                        end
                        
                        ACK_REG: begin
                            state <= RX_DATA; bit_cnt <= 7; sda_oe <= 0;
                        end
                        
                        RX_DATA: begin
                            if (bit_cnt == 0) begin
                                case (active_ptr)
                                    8'h00: reg_ctrl_stat <= shift_reg;
                                    8'h04: reg_i2c_addr  <= shift_reg;
                                    8'h08: reg_wr_data   <= shift_reg;
                                    8'h0C: reg_rd_data   <= shift_reg;
                                    8'h10: reg_length    <= shift_reg;
                                    8'h14: reg_config    <= shift_reg;
                                    default: if (active_ptr >= 8'h20 && active_ptr < 8'h20+MAX_DATA_BYTES)
                                                 data_buffer[active_ptr - 8'h20] <= shift_reg;
                                endcase
                                state <= ACK_DATA; sda_oe <= 1'b1;
                            end else bit_cnt <= bit_cnt - 1'b1;
                        end
                        
                        ACK_DATA: begin
                            state <= RX_DATA; bit_cnt <= 7; sda_oe <= 0;
                            active_ptr <= active_ptr + 1'b1;
                        end
                        
                        TX_DATA: begin
                            if (bit_cnt == 0) begin
                                state <= WAIT_ACK; sda_oe <= 0;
                            end else begin
                                bit_cnt <= bit_cnt - 1'b1;
                                tx_shift <= {tx_shift[6:0], 1'b0};
                                sda_oe <= ~tx_shift[6];
                            end
                        end
                        
                        WAIT_ACK: begin
                            if (master_ack == 1'b0) begin // FIX: Use the securely sampled ACK register
                                state <= PREP_TX; bit_cnt <= 7; stretch_req <= 1'b1;
                                active_ptr <= active_ptr + 1'b1;
                            end else begin
                                state <= IDLE; sda_oe <= 0;
                            end
                        end
                        default: state <= IDLE;
                    endcase
                end
            end
        end
    end
endmodule