// packet_dynarray.sv -- a randomized dynamic array inside a class, collected in a queue of handles.
// Companion to docs/01-sv-fundamentals/01-data-types.md ("Dynamic arrays").
//
// randomize() resizes `payload` to satisfy the size() constraint; new[] is never called by hand.
// Each iteration allocates a fresh object so the queue holds five distinct packets.
//   vlog -sv packet_dynarray.sv && vsim -c packet_dynarray -do "run -all; quit"

class packet;
  rand byte payload[];                                    // randomized payload as a dynamic array
  constraint c_len { payload.size() inside {[1:64]}; }    // constrain the length, not the contents

  function void display();
    $display("packet size = %0d, data = %p", payload.size(), payload);
  endfunction
endclass

module packet_dynarray;
  initial begin
    packet pkt_q[$];   // queue of packet handles
    packet p;

    repeat (5) begin
      p = new();
      assert(p.randomize());  // gets a fresh random size each time
      pkt_q.push_back(p);
    end

    foreach (pkt_q[i]) pkt_q[i].display();
    $finish;
  end
endmodule
