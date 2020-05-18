#!/bin/sh 
if ! test -f ../prototxt/Full_640x640/Centerface_v2_train.prototxt ;then 
   echo "error: ../prototxt/Full_640x640/Centerface_v2_train.prototxt does not exit." 
   echo "please generate your own model prototxt primarily." 
   exit 1 
if ! test -f ../prototxt/Full_640x640/Centerface_v2_test.prototxt ;then 
   echo "error: ../prototxt/Full_640x640/Centerface_v2_test.prototxt does not exit." 
   echo "please generate your own model prototxt primarily." 
   exit 1 
../../../../build/tools/caffe train --solver=../prototxt/Full_640x640/Centerface_v2_solver.prototxt --gpu 0 \
# --snapshot=../snapshot/Centerface_v2_iter_5000.solverstate 