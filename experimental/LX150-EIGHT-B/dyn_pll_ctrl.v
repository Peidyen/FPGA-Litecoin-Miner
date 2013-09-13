module dyn_pll_ctrl # (parameter SPEED_MHZ = 25, parameter SPEED_LIMIT = 100, parameter OSC_MHZ = 100)
	(clk,
	clk_valid,
	speed_in,
	start,
	progclk,
	progdata,
	progen,
	reset,
	locked,
	status);

	input clk;				// NB Assumed to be 12.5MHz uart_clk
	input clk_valid;		// Drive from LOCKED output of first dcm (ie uart_clk valid)
	input [7:0] speed_in;
	input start;
	output reg progclk = 0;
	output reg progdata = 0;
	output reg progen = 0;
	output reg reset = 0;
	input locked;
	input [2:1] status;

	// TODO watchdog on dcm_status ... reset if invalid for too long
	
	// NB spec says to use (dval-1) and (mval-1), but I don't think we need to be that accurate
	//    and this saves a pair of adders. Feel free to amend it.
	reg [7:0] state = 0;
	reg [7:0] dval = OSC_MHZ;	// Osc clock speed (hence mval scales in MHz)
	reg [7:0] mval = SPEED_MHZ;
	reg start_d1 = 0;
	
	always @ (posedge clk)
	begin
		progclk <= ~progclk;
		start_d1 <= start;
		
		if (~clk_valid)			// Try not to run while clk is unstable
		begin
			progen <= 0;
			progdata <= 0;
			state <= 0;
		end
		else
		begin
		
			// The documentation is unclear as to whether the DCM loads data on positive or negative edge. The timing
			// diagram unhelpfully shows data changing on the positive edge, which could mean either its sampled on
			// negative, or it was clocked on positive! However the following says NEGATIVE ...
			// http://forums.xilinx.com/t5/Spartan-Family-FPGAs/Spartan6-DCM-CLKGEN-does-PROGCLK-have-a-maximum-period-minimum/td-p/175642
			// BUT this can lock up the DCM, positive clock seems more reliable (but it can still lock up for low values of M).
			// TODO sort this issue out properly and implement a watchdog.
		
			if ((start || start_d1) && state==0 && speed_in != 0 && speed_in < SPEED_LIMIT && progclk==1)	// positive clock
			// if ((start || start_d1) && state==0 && speed_in != 0 && speed_in < SPEED_LIMIT && progclk==0)	// negative clock
			begin
				progen <= 0;
				progdata <= 0;
				mval <= speed_in;
				dval <= OSC_MHZ;
				state <= 1;
			end
			if (state != 0)
				state <= state + 1'd1;
			case (state)		// Even values to sync with progclk
				// Send D
				2: begin
					progen <= 1;
					progdata <= 1;
				end
				4: begin
					progdata <= 0;
				end
				6,8,10,12,14,16,18,20: begin
					progdata <= dval[0];
					dval[6:0] <= dval[7:1];
				end
				22: begin
					progen <= 0;
					progdata <= 0;
				end
				// Send M
				32: begin
					progen <= 1;
					progdata <= 1;
				end
				36,38,40,42,44,46,48,50: begin
					progdata <= mval[0];
					mval[6:0] <= mval[7:1];
				end
				52: begin
					progen <= 0;
					progdata <= 0;
				end
				// Send GO - NB 1 clock cycle
				62: begin
					progen <= 1;
				end
				64: begin
					progen <= 0;
				end
				// We should wait on progdone/locked, but just go straight back to idle
				254: begin
					state <= 0;
				end
			endcase
		end
	end
endmodule
