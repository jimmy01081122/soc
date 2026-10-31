# Out-of-context synthesis (and optionally implementation) of a module exported by
# scripts/export_vivado.sh, targeting the PYNQ-Z2's XC7Z020.
#
# Run it from an empty work directory; reports and a checkpoint land there:
#
#   vivado -mode batch -source <repo>/vivado/synth_ooc.tcl \
#          -tclargs <repo>/vivado/<CONFIG>/<TOP> [clock_period_ns] [impl]
#
#   clock_period_ns  target period for the clock port, default 10.0 (100 MHz)
#   impl             also run opt/place/route and report post-route numbers
#
# Synthesis-only timing has no routing delay, so treat its slack as optimistic;
# the post-route numbers (impl) are the ones to quote for Fmax.
#
# NOTE: written without access to Vivado; the Verilog it reads was lint-checked
# with Verilator only. Report any error from this script verbatim.

if {$argc < 1} {
    puts "usage: vivado -mode batch -source synth_ooc.tcl -tclargs <export_dir> \[period_ns\] \[impl\]"
    exit 1
}
set export_dir [file normalize [lindex $argv 0]]
set period     [expr {$argc > 1 ? [lindex $argv 1] : 10.0}]
set run_impl   [expr {$argc > 2 && [lindex $argv 2] eq "impl"}]

set top  [file tail $export_dir]
set cfg  [file tail [file dirname $export_dir]]
set part xc7z020clg400-1
set tag  ${cfg}_${top}_[expr {int($period)}]ns

# --- read sources (files.txt lists them in a fixed order; all are read as SystemVerilog)
set fh [open [file join $export_dir files.txt] r]
set names [split [string trim [read $fh]] "\n"]
close $fh
foreach n $names {
    read_verilog -sv [file join $export_dir rtl $n]
}
puts "read [llength $names] files for top $top"

# --- synthesis
synth_design -top $top -part $part -mode out_of_context
create_clock -period $period -name clock [get_ports clock]

write_checkpoint -force ${tag}_synth.dcp
report_utilization              -file ${tag}_synth_utilization.rpt
report_utilization -hierarchical -file ${tag}_synth_utilization_hier.rpt
report_timing_summary -max_paths 10 -file ${tag}_synth_timing.rpt
# available in newer Vivado versions only
catch {report_ram_utilization   -file ${tag}_synth_ram.rpt}

# --- optional implementation
if {$run_impl} {
    opt_design
    place_design
    route_design
    write_checkpoint -force ${tag}_routed.dcp
    report_utilization -file ${tag}_route_utilization.rpt
    report_timing_summary -max_paths 10 -file ${tag}_route_timing.rpt
}

puts "done: reports are in [pwd] with prefix $tag"
