#!/bin/sh
if ! test -f ../../prototxt/detect_with_blur_occlu/face_train_v4.prototxt ;then
	echo "error: ../../prototxt/detect_with_blur_occlu/face_train_v4.prototxt does not exit."
	echo "please generate your own model prototxt primarily."
        exit 1
fi
if ! test -f ../../prototxt/detect_with_blur_occlu/face_test_v4.prototxt ;then
	echo "error: ../../prototxt/detect_with_blur_occlu/face_test_v4.prototxt does not exit."
	echo "please generate your own model prototxt primarily."
        exit 1
fi
../../../../../build/tools/caffe train --solver=../../solver/solver_with_blur_occlu/solver_train_v4.prototxt -gpu 3 \
#--snapshot=../../snapshot/face_detector_with_v4_iter_6791.solverstate
