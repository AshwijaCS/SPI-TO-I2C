module clock_gen (
    input  wire clk_50mhz,
    input  wire rst_n_async,
    output reg  clk_spi
);
    reg [2:0] div_cnt;
    
    always @(posedge clk_50mhz or negedge rst_n_async) begin
        if (!rst_n_async) begin
            div_cnt <= 3'd0;
            clk_spi <= 1'b0;
        end else begin
            if (div_cnt == 3'd4) begin
                div_cnt <= 3'd0;
                clk_spi <= ~clk_spi;
            end else begin
                div_cnt <= div_cnt + 1'b1;
            end
        end
    end
endmodule