// rt_stimulator.sv - Stimulator module to drive input signals

module rt_stimulator(rt_interface intf);
  typedef enum {ST_RESET, ST_IDLE, ST_ADDR, ST_PAD, ST_DATA} stim_state_t;
  stim_state_t dbg_state;
  byte unsigned dbg_din_chnl0_data;
  int ch_status[int];

  rt_packet_t pkts_q[$];

  // Enqueue packet to stimulator
  function void put_pkt(input rt_packet_t pkt);
    pkts_q.push_back(pkt);
  endfunction

  // Drive reset
  initial begin : stim_reset_proc
    apply_reset();
  end

  task apply_reset();
    @(negedge intf.reset_n);
    dbg_state <= ST_RESET;
    intf.din <= 0;
    intf.frame_n <= '1;
    intf.valid_n <= '1;
  endtask

  // Channel data transfer process
  initial begin : stim_ch_proc
    @(negedge intf.reset_n);
    repeat(10) @(posedge intf.clock);
    forever begin
      automatic rt_packet_t pkt;
      wait(pkts_q.size() > 0);
      pkt = pkts_q.pop_front();
      fork
        begin
          wait_ch_avail(pkt);
          drive_pkt(pkt.src_ch, pkt.dst_ch, pkt.payload);
          set_ch_avail(pkt);
        end
      join_none
    end
  end

  // Check if channel is available
  task automatic wait_ch_avail(rt_packet_t pkt);
    if (!ch_status.exists(pkt.src_ch))
      ch_status[pkt.src_ch] = pkt.dst_ch;
    else if (ch_status[pkt.src_ch] >= 0)
      wait(ch_status[pkt.src_ch] == -1);
  endtask

  // Mark channel as available
  function automatic set_ch_avail(rt_packet_t pkt);
    ch_status[pkt.src_ch] = -1;
  endfunction

  // Drive packet to channel
  task automatic drive_pkt(bit[3:0] saddr, bit[3:0] daddr, byte unsigned data[]);
    $display("@%0t: [STIM] src_ch[%0d], dst_ch[%0d] data trans started", $time, saddr, daddr);

    for (int i = 0; i < 4; i++) begin
      @(posedge intf.clock);
      dbg_state <= ST_ADDR;
      intf.din[saddr] <= daddr[i];
      intf.valid_n[saddr] <= $urandom_range(0,1);
      intf.frame_n[saddr] <= 1'b0;
    end

    for (int i = 0; i < 5; i++) begin
      @(posedge intf.clock);
      dbg_state <= ST_PAD;
      intf.din[saddr] <= 1'b1;
      intf.valid_n[saddr] <= 1'b1;
      intf.frame_n[saddr] <= 1'b0;
    end

    foreach (data[idx]) begin
      for (int i = 0; i < 8; i++) begin
        @(posedge intf.clock);
        dbg_state <= ST_DATA;
        dbg_din_chnl0_data <= data[idx];
        intf.din[saddr] <= data[idx][i];
        intf.valid_n[saddr] <= 1'b0;
        intf.frame_n[saddr] <= (idx == data.size() - 1 && i == 7) ? 1'b1 : 1'b0;
      end
    end

    @(posedge intf.clock);
    dbg_state <= ST_IDLE;
    dbg_din_chnl0_data <= 0;
    intf.din[saddr] <= 1'b0;
    intf.valid_n[saddr] <= 1'b1;
    intf.frame_n[saddr] <= 1'b1;
    $display("@%0t: [STIM] src_ch[%0d], dst_ch[%0d] data trans finished", $time, saddr, daddr);
  endtask
endmodule
