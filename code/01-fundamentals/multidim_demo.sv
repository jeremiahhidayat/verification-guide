// multidim_demo.sv -- 3-D packed vs 3-D unpacked arrays.
// Companion to docs/01-sv-fundamentals/01-data-types.md ("Worked example: a 3-D array ...").
//   vlog -sv multidim_demo.sv && vsim -c multidim_demo -do "run -all; quit"

module multidim_demo;
  initial begin
    // (a) 3-D PACKED: one 512-bit vector, sliceable as [plane][row][bit]
    logic [7:0][7:0][7:0] cube_p;
    // (b) 3-D UNPACKED: 8x8 separate 8-bit elements
    logic [7:0] cube_u [8][8];

    cube_p = '0;
    cube_p[0][0] = 8'hF;            // one byte; element [0][0] is bits [7:0] of the vector
    cube_p[7][7] = 8'hA5;           // bits [511:504]
    $display("packed: %h", cube_p);
    $display("packed slice [7] = %h, [7][7] = %h", cube_p[7], cube_p[7][7]);

    cube_u = '{default: 8'h0};      // assignment pattern; '{...} not {...}
    cube_u[0][0] = 8'hF;
    cube_u[1] = '{8{8'hFF}};        // replicate: whole row
    $display("unpacked: %p", cube_u);

    foreach (cube_u[i, j])          // two indexes, one loop: comma form for unpacked dims
      if (cube_u[i][j] != 0) $display("cube_u[%0d][%0d] = %h", i, j, cube_u[i][j]);
    $finish;
  end
endmodule
