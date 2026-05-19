
iverilog.exe -D IVERILOG -o tb_Core.vvp .\tb_Core.v ..\source\Core.v

pause

vvp tb_Core.vvp 

gtkwave tb_Core.vcd

pause
