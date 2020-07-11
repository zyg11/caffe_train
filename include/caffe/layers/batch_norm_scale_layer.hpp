#ifndef CAFFE_BATCHNORM_SCALE_LAYER_HPP_
#define CAFFE_BATCHNORM_SCALE_LAYER_HPP_

#include <vector>

#include "caffe/blob.hpp"
#include "caffe/layer.hpp"
#include "caffe/proto/caffe.pb.h"

namespace caffe {

/**
 * @brief Normalizes the input to have 0-mean and/or unit (1) variance across
 *        the batch.
 *
 * This layer computes Batch Normalization as described in [1]. For each channel
 * in the data (i.e. axis 1), it subtracts the mean and divides by the variance,
 * where both statistics are computed across both spatial dimensions and across
 * the different examples in the batch.
 *
 * By default, during training time, the network is computing global
 * mean/variance statistics via a running average, which is then used at test
 * time to allow deterministic outputs for each input. You can manually toggle
 * whether the network is accumulating or using the statistics via the
 * use_global_stats option. For reference, these s0tatistics are kept in the
 * layer's three blobs: (0) mean, (1) variance, and (2) moving average factor.
 *
 * Note that the original paper also included a per-channel learned bias and
 * scaling factor. To implement this in Caffe, define a `ScaleLayer` configured
 * with `bias_term: true` after each `BatchNormScaleLayer` to handle both the bias
 * and scaling factor.
 * Computes the elementwise product of two input Blobs, with the shape of
 *        the latter Blob "broadcast" to match the shape of the former.
 *        Equivalent to tiling the latter Blob, then computing the elementwise
 *        product. Note: for efficiency and convenience, this layer can
 *        additionally perform a "broadcast" sum too when `bias_term: true`
 *        is set.
 *
 * The latter, scale input may be omitted, in which case it's learned as
 * parameter of the layer (as is the bias, if it is included).
 *
 * [1] S. Ioffe and C. Szegedy, "Batch Normalization: Accelerating Deep Network
 *     Training by Reducing Internal Covariate Shift." arXiv preprint
 *     arXiv:1502.03167 (2015).
 *
 * TODO(dox): thorough documentation for Forward, Backward, and proto params.
 */
template <typename Dtype>
class BatchNormScaleLayer : public Layer<Dtype> {
    public:
        explicit BatchNormScaleLayer(const LayerParameter& param)
            : Layer<Dtype>(param) {}
        virtual void LayerSetUp(const vector<Blob<Dtype>*>& bottom,
            const vector<Blob<Dtype>*>& top);
        virtual void Reshape(const vector<Blob<Dtype>*>& bottom,
            const vector<Blob<Dtype>*>& top);

        virtual inline const char* type() const { return "BatchNormScale"; }
        virtual inline int ExactNumBottomBlobs() const { return 1; }
        virtual inline int ExactNumTopBlobs() const { return 1; }

    protected:
        virtual void Forward_cpu(const vector<Blob<Dtype>*>& bottom,
            const vector<Blob<Dtype>*>& top);
        virtual void Forward_gpu(const vector<Blob<Dtype>*>& bottom,
            const vector<Blob<Dtype>*>& top);
        virtual void Backward_cpu(const vector<Blob<Dtype>*>& top,
            const vector<bool>& propagate_down, const vector<Blob<Dtype>*>& bottom);
        virtual void Backward_gpu(const vector<Blob<Dtype>*>& top,
            const vector<bool>& propagate_down, const vector<Blob<Dtype>*>& bottom);

        Blob<Dtype> mean_, variance_, x_norm_;
        bool use_global_stats_;
        Dtype moving_average_fraction_;
        int channels_;
        Dtype eps_;

        // extra temporarary variables is used to carry out sums/broadcasting
        // using BLAS
        Blob<Dtype> batch_sum_multiplier_;
        Blob<Dtype> num_by_chans_;
        Blob<Dtype> spatial_sum_multiplier_;
        // scale-parameter
        Blob<Dtype> bias_multiplier_;
        int axis_, outer_dim_, scale_dim_, inner_dim_;
};

}  // namespace caffe

#endif  // CAFFE_BATCHNORM_LAYER_HPP_
