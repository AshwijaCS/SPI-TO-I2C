module rst_sync (
    input  wire clk,
    input  wire rst_n_in,
    output reg  rst_n_out
);
    reg sync_0, sync_1;

    always @(posedge clk or negedge rst_n_in) begin
        if (!rst_n_in) begin
            sync_0    <= 1'b0;
            sync_1    <= 1'b0;
            rst_n_out <= 1'b0;
        end else begin
            sync_0    <= 1'b1;
            sync_1    <= sync_0;
            rst_n_out <= sync_1;
        end
    end
endmodule