`include "subcounter.sv"

module shared_counters(clk,rst,command_in,id,data_out,new_counter_size,allocation_id,valid_allocation_id,rdata_out,valid_data_out,last,load_data_in,valid_load_data); 

// Parameters
parameter n=10; 	//o arithmos twn subcounter
parameter g=4; 	//o arithmos bits ana subcounter

// Port declarations
// input ports
input wire clk;
input wire rst;
input wire [2:0] command_in;
input wire [$clog2(n)-1:0]id;
input integer new_counter_size;
// output ports
output reg [g-1:0] data_out[n-1:0];
output reg valid_allocation_id;
output reg [$clog2(n):0] allocation_id;
output reg valid_data_out;
output reg [g-1:0] rdata_out;
output reg last;

// Signals declaration
// Generate signals
reg [1:0] mask_sub_command_in [n-1:0];
reg [g-1:0] data_in[n-1:0];
reg [n-1:0]load_en;
// Command decode signals
enum { idle, reset, increment, new_counter,deallocation, load, read } command;
// subcounter_of_counter signals
reg [n-1:0] subcounter_of_counter, free,shift_mask,local_mask,or_local_mask,mask;
reg [$clog2(n)-1:0]local_id;
// Allocation signals
reg [n-1:0] local_vector,candidate,mask_candidate,final_candidate;
// Subcommand signals
reg [1:0] sub_command_in [n-1:0];
// Mask subcommand signals
reg [n-1:0] local_mask_sub_command_in;
// Read signals
reg [$clog2(n)-1:0] cycle_counter;
// Load signals
reg [63:0] temp_load_data;
input wire [63:0] load_data_in;
input wire valid_load_data;
reg valid_temp_load_data;
reg [$clog2(n)-1:0]temp_id;

///// END of signals declaration

// generate subcounters
generate
	genvar i;
	for (i = 0; i < n; i=i+1) begin
		subcounter #(.granularity(g)) subcounter_i(
						.clk(clk),
						.sub_command_in(mask_sub_command_in[i]),
						.load_data_in(data_in[i]),
						.data_out(data_out[i]),
						.load_en(load_en[i])
						);
	end
endgenerate



//command decode
//command_in -> command(idle, reset, increment, new_counter)
always @(command_in or rst) begin : command_decode
	if(rst==1'b1) begin
		command = reset;
	end else if(command_in==3'b000) begin
		command = idle;
	end else if(command_in==3'b001) begin
		command = increment;
	end else if(command_in==3'b010) begin
		command = new_counter;
	end else if (command_in==3'b011) begin
		command = deallocation;
	end else if(command_in==3'b100) begin
		command = load;
	end else if(command_in==3'b101) begin
		command = read;
	end
end


// subcounter_of_counter: dinei ena vector apo poious subcounter apoteleitai o counter(id)
always @(*) begin //command or id or mask or free or subcounter_of_counter
if (command==increment || command==deallocation || command==read || valid_temp_load_data || command==load) begin
	if (valid_temp_load_data==1'b1) begin
		local_id=temp_id;
	end else begin
		local_id = id;
	end
	shift_mask = (mask >>local_id+1);
	local_mask= (shift_mask <<local_id+1);
	for (int i =n-1; i>=0;i=i-1)begin
		if (i<local_id) begin
			subcounter_of_counter[i]=1'b0;
		end else if (i==local_id) begin
			subcounter_of_counter[i]=mask[i] && ~free[i];
		end else if (i>local_id) begin
			if (|local_mask==1'b1 || free[i]==1'b1) begin 		// na elenksw oti leitourgei kala me to free[i]
				subcounter_of_counter[i]=1'b0;
			end else begin
				subcounter_of_counter[i]=1'b1;
			end
			local_mask= local_mask<<1;
			//$display("local_mask[%d]=%b",i,subcounter_of_counter);
		end
	end
end
end

// Allocation
// new_counter
always @(*) begin
	if (command==new_counter) begin
		for (int i=0;i<n;i=i+1)begin
			local_vector[i] = (i<new_counter_size) ? 1:0;
		end

		for (int i=0;i<n;i=i+1)begin
			local_vector = (i>0) ? (local_vector<<1):local_vector;
			candidate[i] = ((free&local_vector)==local_vector) ? 1:0;
		end
		
		for (int i=0;i<n;i=i+1)begin
			if (i<new_counter_size) begin
				candidate = candidate<<i;
				candidate = candidate>>i;
			end 
		end

		mask_candidate=candidate;
		for (int i=n-1; i>=0; i=i-1)begin
			mask_candidate = mask_candidate<<1;
			if ((candidate[i]==1'b1) && ((|mask_candidate)==1'b0) ) begin
				final_candidate[i]=1'b1;
			end else begin
				final_candidate[i]=0;
			end
		end

		if (|final_candidate==1'b1) begin
			for(int i=0;i<n;i=i+1)begin
				if (final_candidate[i]==1'b1) begin
					allocation_id=i;
					valid_allocation_id=1'b1;
					mask[i]=1'b1;
				end
			end
			
		end else begin
			allocation_id=0;
			valid_allocation_id=1'b0;
		end
		
		for (int i=0;i<n;i=i+1)begin
			if (valid_allocation_id==1'b1 && i>=allocation_id && i<allocation_id+new_counter_size) begin
				free[i]=0;
			end else begin
				free[i]=free[i];
			end
		end
		$display("Allocation done, size=%d", new_counter_size);
		$display("free=%b",free);
		$display("mask=%b",mask);

	end else begin
		allocation_id=0;
		valid_allocation_id=1'b0;
	end
end

// Deallocation
always @(*) begin
	if (command==deallocation) begin
		for (int i=0;i<n;i=i+1)begin
			if (mask[id]==1'b1) begin
				if (subcounter_of_counter[i]==1'b1) begin
					if (i==id) begin
						mask[i]=0;
					end
					free[i]=1;
				end else begin
					mask[i]=mask[i];
					free[i]=free[i];
				end
			end
			
		end

		$display("De-Allocation done, counter_id=%d", id);
		$display("mask=%b",mask);
		$display("free=%b",free);	
	end
end



// analoga me to command moirazw tis katalliles entoles stous subcounter 
// (prosoxi dn einai oi telikes entoles pou tha paroun oi subcounter, oi telikes dinontai apo to mask_sub_command_in)
always @(*) begin
if (command==increment) begin
	for (int i=0; i<n; i=i+1)begin
		if (subcounter_of_counter[i]==1'b1) begin
			if (&data_out[i]==1'b1) begin
				sub_command_in[i]=2'b00; // id data_out[i]="1111" then reset
			end else begin
				sub_command_in[i]=2'b01; // else increment
			end
		end else begin
			sub_command_in[i]=2'b10; // is subcounter doesnt belong to counter set idle
		end
		//$display("sub_command_in[%d]=%b",i,sub_command_in[i]);
	end
end else if(command==idle) begin
	for(int i=0;i<n;i=i+1)begin
		sub_command_in[i]=2'b10; // set every subcounter idle
	end
end else if (command==reset) begin
	free={n{1'b1}};
	mask={n{1'b0}};
	for(int i=0;i<n;i=i+1)begin
		sub_command_in[i]=2'b00; // set every subcounter reset
	end
end
end


// mask_sub_command_in: metatrepw tis entoles sub_command_in stis swstes entoles pou dinontai stous subcounter
// oi entoles sub_command_in edinan tis entoles increment/reset mono koitazontas tin eksodo twn subcounter (an ola 1 tote reset alliws increment )
// me tis masked entoles elegxw mexri na dwsw to 1o increment se subcounter kai dinw entoli idle stous subcounter meta apo auton
always @(*) begin
	for (int i=0;i<n;i=i+1)begin
		if (sub_command_in[i]==2'b01) begin
			local_mask_sub_command_in[i]=1'b1;
		end else if (sub_command_in[i]==2'b00 || sub_command_in[i]==2'b10) begin
			local_mask_sub_command_in[i]=1'b0;
		end
	end

	for (int i=n-1; i>=0;i=i-1)begin
		local_mask_sub_command_in = local_mask_sub_command_in<<1;
		//$display("local_mask_sub_command_in[%d]=%b",i,local_mask_sub_command_in);
		if (|local_mask_sub_command_in==1'b1 || subcounter_of_counter[i]==1'b0) begin
			mask_sub_command_in[i]=2'b10; // set idle 
		end else if (|local_mask_sub_command_in==1'b0) begin
			mask_sub_command_in[i]=sub_command_in[i]; //pass increment or reset
		end
	end
end

// READ
always @(posedge clk or posedge rst) begin
	if (rst) begin
		rdata_out<={g{0}};
		cycle_counter<=0;
		valid_data_out<=0;
	end
	else if (command==read) begin
		cycle_counter<= cycle_counter+1;
		if (subcounter_of_counter[id+cycle_counter]==1'b1) begin
			rdata_out<=data_out[id+cycle_counter];
			valid_data_out<=1'b1;
			if (id+cycle_counter+1<n) begin
				if (subcounter_of_counter[id+cycle_counter+1]==1'b0) begin
					last<=1'b1;
				end else
					last<=1'b0;
			end
		end else begin
			rdata_out<={g{0}};
			valid_data_out<=0;
		end
	end else begin
		rdata_out<={g{0}};
		cycle_counter<=0;
		valid_data_out<=0;
	end
end


//LOAD
//external load
always @(posedge clk or posedge rst) begin
	if (command==load && valid_load_data==1'b1) begin
		temp_load_data<=load_data_in;
		valid_temp_load_data<=1'b1;
		temp_id<=id;
	end else begin
		temp_load_data<=0;
		valid_temp_load_data<=0;
		temp_id<=0;
	end
end

//internal load
always @(*) begin
	for (int i=0; i<n; i=i+1)begin
		if (valid_temp_load_data==1'b1 && subcounter_of_counter[i]==1'b1) begin
			data_in[i]=temp_load_data[(i-temp_id)*g+:g];
			load_en[i]=1'b1;
			
		end else begin
			load_en[i]=0;
		end

		/*if (valid_temp_load_data==1'b1 ) begin
			$display ("data_in[%d]=%b",i, temp_load_data[(i-temp_id)*g+:g]);
			$display ("subcounter_of_counter=%b", subcounter_of_counter);
		end*/
	end
end


endmodule