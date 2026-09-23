module packet_parser #(
    parameter MAX_DATA_BYTES = 16,
    parameter I2C_SLAVE_ADDR = 7'h50
)(
    input  wire       clk_sys,
    input  wire       rst_n,
    
    input  wire [7:0] fifo_data,
    input  wire       fifo_empty,
    output reg        fifo_rd_en,
    
    input  wire [7:0] rd_data,
    input  wire       busy,
    
    output reg  [7:0] i2c_addr,
    output reg  [7:0] reg_addr,
    output reg  [7:0] length,
    output reg        reg_wr_en,
    output reg        reg_rd_en,
    output reg  [7:0] wr_data,
    output reg        ack_error
);
    localparam [3:0] IDLE         = 4'd0,
                     WAIT_I2C     = 4'd1,
                     GET_I2C      = 4'd2,
                     WAIT_REG     = 4'd3,
                     GET_REG      = 4'd4,
                     WAIT_LEN     = 4'd5,
                     GET_LEN      = 4'd6,
                     WAIT_DATA    = 4'd7,
                     GET_DATA     = 4'd8,
                     COMMIT_WRITE = 4'd9,
                     COMMIT_READ  = 4'd10,
                     ERROR_ST     = 4'd11;
                     
    reg [3:0] state;
    
    reg [7:0] cmd_reg;
    reg cmd_valid;
    reg [7:0] internal_buf [0:MAX_DATA_BYTES-1];
    reg [4:0] byte_idx;
    reg [7:0] target_reg_addr;
    integer i;

    always @(posedge clk_sys or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            fifo_rd_en <= 1'b0;
            reg_wr_en  <= 1'b0;
            reg_rd_en  <= 1'b0;
            ack_error  <= 1'b0;
            cmd_valid  <= 1'b0;
            i2c_addr   <= 8'h00;
            reg_addr   <= 8'h00;
            length     <= 8'h00;
            wr_data    <= 8'h00;
            byte_idx   <= 5'd0;
            target_reg_addr <= 8'h00;
            cmd_reg    <= 8'h00;
            for(i=0; i<MAX_DATA_BYTES; i=i+1) begin
                internal_buf[i] <= 8'h00;
            end
        end else begin
            fifo_rd_en <= 1'b0;
            reg_wr_en  <= 1'b0;
            reg_rd_en  <= 1'b0;
            ack_error  <= 1'b0;

            case (state)
                IDLE: begin
                    if (!fifo_empty) begin
                        fifo_rd_en <= 1'b1;
                        if (fifo_data == 8'h01 || fifo_data == 8'h02) begin
                            cmd_reg <= fifo_data;
                            cmd_valid <= 1'b1;
                            state <= WAIT_I2C;
                        end else begin
                            cmd_valid <= 1'b0;
                            ack_error <= 1'b1; 
                            state <= ERROR_ST;
                        end
                    end
                end
                
                WAIT_I2C: begin
                    state <= GET_I2C;
                end
                
                GET_I2C: begin
                    if (!fifo_empty) begin
                        i2c_addr <= fifo_data;
                        fifo_rd_en <= 1'b1;
                        if (fifo_data != {1'b0, I2C_SLAVE_ADDR[6:0]}) state <= ERROR_ST;
                        else state <= WAIT_REG;
                    end
                end
                
                WAIT_REG: state <= GET_REG;
                
                GET_REG: begin
                    if (!fifo_empty) begin
                        target_reg_addr <= fifo_data;
                        fifo_rd_en <= 1'b1;
                        state <= WAIT_LEN;
                    end
                end
                
                WAIT_LEN: state <= GET_LEN;
                
                GET_LEN: begin
                    if (!fifo_empty) begin
                        length <= fifo_data;
                        fifo_rd_en <= 1'b1;
                        if (fifo_data == 0 || fifo_data > MAX_DATA_BYTES) state <= ERROR_ST;
                        else if (cmd_reg == 8'h01) begin
                            state <= WAIT_DATA;
                            byte_idx <= 0;
                        end else state <= COMMIT_READ; 
                    end
                end
                
                WAIT_DATA: state <= GET_DATA;
                
                GET_DATA: begin
                    if (!fifo_empty) begin
                        internal_buf[byte_idx] <= fifo_data;
                        fifo_rd_en <= 1'b1;
                        if (byte_idx == length - 1'b1) begin
                            state <= COMMIT_WRITE;
                            byte_idx <= 0;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                            state <= WAIT_DATA;
                        end
                    end
                end
                
                COMMIT_WRITE: begin
                    if (!busy) begin
                        wr_data   <= internal_buf[byte_idx];
                        reg_wr_en <= 1'b1;
                        
                        // FIXED: Calculate address dynamically based on current byte index
                        reg_addr  <= target_reg_addr + byte_idx; 
                        
                        if (byte_idx == length - 1'b1) begin
                            state <= IDLE;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                        end
                    end
                end
                
                COMMIT_READ: begin
                    if (!busy) begin
                        reg_addr  <= target_reg_addr;
                        reg_rd_en <= 1'b1;
                        state     <= IDLE;
                    end
                end
                
                ERROR_ST: begin
                    ack_error <= 1'b1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule