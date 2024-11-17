interface router_io(input bit clock);
  parameter time simulation_cycle = (100*1ns);
  logic		reset_n;
  logic [15:0]	din;
  logic [15:0]	frame_n;
  logic [15:0]	valid_n;
  logic [15:0]	dout;
  logic [15:0]	valido_n;
  logic [15:0]	busy_n;
  logic [15:0]	frameo_n;

  // TYPE definition below
  // We re-clarify the packet class below instead of importing it for ease of
  // use for plug in user's environment
  // import router_test_pkg::packet
  parameter int CHNL_NUM = 16;
  // TODO (Optional as students' vacation home work)
  // BUSY_STATE is not implemented in router, the buffer feature for same
  // DA receiving different SA would be optionally implemented and verified
  typedef enum bit[2:0] {IDLE_STATE, ADDRESS_STATE, PAD_STATE, PAYLOAD_STATE} chnl_state_t;
  class packet;
    logic[3:0] sa;
    logic[3:0] da;
    logic[7:0] payload[];
  endclass

  chnl_state_t [CHNL_NUM-1:0] chnls_state;

  // check if all channles would coordiate together
  covergroup all_channels_work_cg @(posedge clock);
    option.name = "all_channels_work_cg";
    FRAME_N: coverpoint frame_n {
      bins all_frame_n = {16'h0};
    }
    VALID_N: coverpoint valid_n {
      bins all_valid_n = {16'h0};
    }
    FRAME_X_VALID: cross FRAME_N, VALID_N; 
    FRAMEO_N: coverpoint frameo_n {
      bins all_frameo_n = {16'h0};
    }
    VALIDO_N: coverpoint valido_n {
      bins all_valido_n = {16'h0};
    }
    FRAMEO_X_VALIDO: cross FRAMEO_N, VALIDO_N;
  endgroup

  // check at least any channles work with another channel in dual
  covergroup dual_channels_work_cg(input int cid1, input cid2) @(chnls_state[cid1], chnls_state[cid2]);
    option.name = $sformatf("dual_channels_ch%0d_x_ch%0d_cg", cid1, cid2);
    option.per_instance = 1;
    type_option.merge_instances = 0;
    SINGLE_CHNL_STATE1: coverpoint chnls_state[cid1] {
      bins idle_state = {IDLE_STATE};
      bins address_state = {ADDRESS_STATE};
      bins pad_state = {PAD_STATE};
      bins payload_state = {PAYLOAD_STATE};
    }
    SINGLE_CHNL_STATE2: coverpoint chnls_state[cid2] {
      bins idle_state = {IDLE_STATE};
      bins address_state = {ADDRESS_STATE};
      bins pad_state = {PAD_STATE};
      bins payload_state = {PAYLOAD_STATE};
    }
    PARA_CHNLS_STATE: cross SINGLE_CHNL_STATE1, SINGLE_CHNL_STATE2; 
  endgroup

  // sample event is not specified but manually called via sample() method
  covergroup single_channel_work_cg(input int id) with function sample(input packet pkt);
    option.name = $sformatf("single_channel_work_cg[%0d]", id);
    option.per_instance = 1;
    type_option.merge_instances = 0;
    DA: coverpoint pkt.da;
    PL_SIZE: coverpoint pkt.payload.size() {
      bins psize[] = {[1:8]};
    }
  endgroup

  all_channels_work_cg all_channels_cg;
  dual_channels_work_cg dual_channels_cgs[CHNL_NUM/2];
  single_channel_work_cg single_channel_cgs[CHNL_NUM];

  initial begin
    // covergroup instances
    all_channels_cg = new();
    foreach(single_channel_cgs[i])  single_channel_cgs[i] = new(i);
    foreach(dual_channels_cgs[i]) dual_channels_cgs[i] = new(i*2, (i*2)+1);
    // monitor packets and sample coverage
    channels_monitor_packets();
  end

  task automatic channels_monitor_packets();
    // monitor CHNL_NUM single channles
    for(int i = 0; i < CHNL_NUM; i++) begin
      automatic int id = i;
      fork
        monitor_packet(id);
      join_none
    end
    // monitor all dual channels
  endtask


  task automatic monitor_packet(input int id);
    packet pkt;
    forever begin
      pkt = new();
      pkt.sa = id;
      mon_addrs(pkt);
      mon_pad(pkt);
      mon_payload(pkt);
      // sample packet coverage once the packet finished
      single_channel_cgs[id].sample(pkt);
    end
  endtask

  task automatic mon_addrs(input packet pkt);
    @(negedge frame_n[pkt.sa]) chnls_state[pkt.sa] = ADDRESS_STATE;
	  for(int i = 0; i<4; i++) begin
      @(negedge clock); // ensure correct data sampling
      pkt.da[i] <= din[pkt.sa];
	  end
  endtask

  task automatic mon_pad(input packet pkt);
    @(posedge clock) chnls_state[pkt.sa] = PAD_STATE;
    repeat(5) @(negedge clock);
    @(posedge clock) chnls_state[pkt.sa] = PAYLOAD_STATE;
  endtask

  task automatic mon_payload(input packet pkt);
    int pl_count = 0;
    forever begin
      pl_count ++;
      pkt.payload = new[pl_count](pkt.payload); // enlarge and copy items
	    for(int i=0; i<8; i++) begin
        @(negedge clock); 
        if(valid_n[pkt.sa] === 0) begin // available for interleaved valid_n = {0, 1}
          pkt.payload[pl_count-1][i] = din[pkt.sa];
          if(frame_n[pkt.sa] === 1) begin
            @(posedge clock) chnls_state[pkt.sa] = IDLE_STATE;
            return; // last data in frame
          end
        end
      end
    end
  endtask

  //--------------------------------------------------------------
  // * Property and Task definition for timing/logic point check
  //--------------------------------------------------------------
  sequence fell_and_keep_low_pseq (sig, n);
    $fell(sig) ##1 (!sig)[*n];
  endsequence

  sequence rose_and_keep_high_pseq (sig, n);
    $rose(sig) ##1 (sig)[*n];
  endsequence

  sequence keep_val_ncycles_pseq (sig, val, n);
    (sig === val)[*n];
  endsequence

  sequence keep_high_and_fell_pseq (sig, n);
    sig[*n] ##1 $fell(sig);
  endsequence

  sequence keep_low_and_rose_pseq (sig, n);
    (!sig)[*n] ##1 $rose(sig);
  endsequence

  task automatic count_in_valid_data_cycles(int id, event se, event fe, output int n);
    @se;
    fork
      @fe;
      forever @(posedge clock) #10ps if(valid_n[id] === 0) n++; // add delay to avoid redundant count
    join_any
    disable fork;
  endtask

  task automatic count_out_valid_data_cycles(int id, event se, event fe, output int n);
    @se;
    fork
      @fe;
      forever @(posedge clock) #10ps if(valido_n[id] === 0) n++; // add delay to avoid redundant count
    join_any
    disable fork;
  endtask

  task automatic in_frame_catch_value_change(int id, logic val, event e);
    @(frame_n[id] iff frame_n[id] === val); 
    -> e;
  endtask

  task automatic in_valid_catch_value_change(int id, logic val, event e);
    @(valid_n[id] iff valid_n[id] === val); 
    -> e;
  endtask

  task automatic in_payload_start_catch(int id, event e);
    @(negedge frame_n[id]);
    repeat(8) @(posedge clock);
    -> e;
  endtask

  task automatic in_payload_finish_catch(int id, event e);
    @(posedge frame_n[id]);
    @(posedge clock);
    -> e;
  endtask

  task automatic out_valid_catch_value_change(int id, logic val, event e);
    @(frameo_n[id] iff frameo_n[id] === val); 
    @(valido_n[id] iff valido_n[id] === val); 
    -> e;
  endtask

  task automatic out_payload_start_catch(int id, event e);
    @(negedge frameo_n[id]);
    // NOTE:: payload started with 2 cycles delay instead of 1 cycle
    repeat(1) @(posedge clock);
    ->e;
  endtask

  task automatic out_payload_finish_catch(int id, event e);
    @(posedge frameo_n[id]);
    @(posedge clock);
    -> e;
  endtask

  //-----------------------------
  // ** Channel IN timing check
  //-----------------------------
  bit assert_disabled[string]; // by default 0 if index no found

  // - While frame_n fell, and kept low within 4 cycles, din should 
  //   then keep high within 5 cycles.
  property in_frame_fell_din_keep_high_prpt(id);
    @(posedge clock) //disable iff(assert_disabled["in_frame_fell_din_keep_high_prpt"])
    fell_and_keep_low_pseq(frame_n[id], 3) |=> keep_val_ncycles_pseq(din[id], 1'b1, 5);
  endproperty

  // - While valid_n kept high with over 5 cycles and fall, it should 
  //   keep low within totally (8*N) cycles.

  task automatic in_valid_data_cycles_check(int id, ref int pass_count, ref int fail_count);
    int ncycles;
    event se, fe;
    forever begin
      fork // wait payload start/finish event
        in_payload_start_catch(id, se);
        in_payload_finish_catch(id, fe);
      join_none
      // count cycles
      count_in_valid_data_cycles(id, se, fe, ncycles);
      if(((ncycles/8) >= 1 && (ncycles%8) == 0)) 
        pass_count++;
      else begin
        fail_count++;
        $error("@%0t in_valid_data_cycles_check[%0d] check failed!", $time, id);
      end
    end
  endtask
  
  //-----------------------------
  // ** Channel IN timing coverage
  //-----------------------------
  
  // TODO
  
  //-----------------------------
  // ** Channel OUT timing check
  //-----------------------------

  // TODO


  //-----------------------------
  // ** Channel OUT timing coverage
  //-----------------------------
  
  // TODO

  
  //--------------------------------------------
  // ** Assert properties and call check tasks
  //--------------------------------------------
  int assert_check_pass_count[string];
  int assert_check_fail_count[string];
  int task_check_pass_count[string];
  int task_check_fail_count[string];
  int assert_check_pass_total_count;
  int assert_check_fail_total_count;
  int task_check_pass_total_count;
  int task_check_fail_total_count;
  int in_frame_keep_low_cycles_check_pass_count;
  int in_frame_keep_low_cycles_check_fail_count;
  generate 
    for (genvar i=0; i<CHNL_NUM; i++) begin
      // property assert
      assert property (in_frame_fell_din_keep_high_prpt(i)) 
        assert_check_pass_count["in_frame_fell_din_keep_high_prpt"]++;
      else begin
        assert_check_fail_count["in_frame_fell_din_keep_high_prpt"]++;
        $error("@%0t in_frame_fell_din_keep_high[%0d] failed", $time, i);
      end

      // task check
      initial begin
        @(posedge reset_n); // wait reset until release
        fork 
          in_valid_data_cycles_check(i
                                     , task_check_pass_count["in_valid_data_cycles_check"]
                                     , task_check_fail_count["in_valid_data_cycles_check"]
                                     );
        join_none
      end
    end
  endgenerate

  bit test_pass_flag = 1;
  function automatic void report();
    assert_check_pass_total_count = assert_check_pass_count.sum();
    assert_check_fail_total_count = assert_check_fail_count.sum();
    task_check_pass_total_count = task_check_pass_count.sum();
    task_check_fail_total_count = task_check_fail_count.sum();
    $display("==================== INTERFACE REPORT =====================");
    $display("router_io assertion check pass count %0d", assert_check_pass_total_count);
    $display("router_io assertion check fail count %0d", assert_check_fail_total_count);
    $display("router_io task check pass count %0d", task_check_pass_total_count);
    $display("router_io task check fail count %0d", task_check_fail_total_count);
    if(assert_check_fail_total_count != 0 || task_check_fail_total_count != 0) test_pass_flag = 0;
    $display("===========================================================");
  endfunction

  // assertion specific control
  function automatic void assert_set_disable(string id);
    assert_disabled[id] = 1;
  endfunction

  function automatic void assert_set_enable(string id);
    assert_disabled[id] = 0;
  endfunction

  // assertion global control
  function automatic void assert_off();
    $assertoff(0, router_test_top);
  endfunction 

endinterface: router_io