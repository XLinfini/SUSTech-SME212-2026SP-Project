
@REM run simulation in modelsim
vsim -do .\my_sim.tcl
pause

gtkwave .\tb_bram.vcd
pause
