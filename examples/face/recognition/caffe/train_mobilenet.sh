#!/bin/sh
if ! test -f ./prototxt/mobilenet/train.prototxt ;then
	echo "error: train.prototxt does not exit."
	echo "please generate your own model prototxt primarily."
        exit 1
fi
../../../../build/tools/caffe train --solver=./prototxt/mobilenet/solver.prototxt -gpu 0 \
#--snapshot=./face_recog/tiny_iter_148441.solverstate
