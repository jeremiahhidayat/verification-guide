// Non-intrusive attachment of fifo_sva to every instance of fifo.
// .* connects by name to fifo's ports AND its internal signals (do_wr, do_rd, wr_ptr, rd_ptr).
bind fifo fifo_sva #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_fifo_sva (.*);
