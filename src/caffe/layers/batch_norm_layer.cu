#include <algorithm>
#include <vector>

#include "caffe/layers/batch_norm_layer.hpp"
#include "caffe/util/math_functions.hpp"

namespace caffe {

template <typename Dtype>
__global__ void batchNorm_forward(int nthreads, int width, int height, int channels, 
                                  Dtype* top_data, const Dtype* mean_data, const Dtype* var_data){
    CUDA_KERNEL_LOOP(index, nthreads){
        const int fc = (index / width / height) % channels;
        const Dtype mean = mean_data[fc];
        const Dtype var = Dtype(1 / var_data[fc]);
        top_data[index] = Dtype((top_data[index] - mean) * var);
    }
}

template <typename Dtype>
void BatchNormLayer<Dtype>::Forward_gpu(const vector<Blob<Dtype>*>& bottom,
    const vector<Blob<Dtype>*>& top) {
    #if 1
    const Dtype* bottom_data = bottom[0]->gpu_data();
    Dtype* top_data = top[0]->mutable_gpu_data();
    int num = bottom[0]->shape(0);
    int spatial_dim = bottom[0]->count()/(channels_*bottom[0]->shape(0));

    if (bottom[0] != top[0]) {
        caffe_copy(bottom[0]->count(), bottom_data, top_data);
    }
    if (use_global_stats_) {
        // use the stored mean/variance estimates.
        const Dtype scale_factor = this->blobs_[2]->cpu_data()[0] == 0 ?
            0 : 1 / this->blobs_[2]->cpu_data()[0];
        caffe_gpu_scale(variance_.count(), scale_factor,
            this->blobs_[0]->gpu_data(), mean_.mutable_gpu_data());
        caffe_gpu_scale(variance_.count(), scale_factor,
            this->blobs_[1]->gpu_data(), variance_.mutable_gpu_data());
    } else {
        // compute mean
        caffe_gpu_gemv<Dtype>(CblasNoTrans, channels_ * num, spatial_dim,
            1. / (num * spatial_dim), bottom_data,
            spatial_sum_multiplier_.gpu_data(), 0.,
            num_by_chans_.mutable_gpu_data());
        caffe_gpu_gemv<Dtype>(CblasTrans, num, channels_, 1.,
            num_by_chans_.gpu_data(), batch_sum_multiplier_.gpu_data(), 0.,
            mean_.mutable_gpu_data());
    }
    // subtract mean, top_data = x - mean(x)
    caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, num, channels_, 1, 1,
        batch_sum_multiplier_.gpu_data(), mean_.gpu_data(), 0.,
        num_by_chans_.mutable_gpu_data());
    caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, channels_ * num,
        spatial_dim, 1, -1, num_by_chans_.gpu_data(),
        spatial_sum_multiplier_.gpu_data(), 1., top_data);

    if (!use_global_stats_) {
        // compute variance using var(X) = E((X-EX)^2)
        caffe_gpu_powx(top[0]->count(), top_data, Dtype(2), top_data);  // (X-EX)^2, 第二个top_data->temp_.mutable_gpu_data()
        caffe_gpu_gemv<Dtype>(CblasNoTrans, channels_ * num, spatial_dim,
            1. / (num * spatial_dim), top_data, spatial_sum_multiplier_.gpu_data(), 
            0., num_by_chans_.mutable_gpu_data()); //top_data ->temp_.gpu_data()
        caffe_gpu_gemv<Dtype>(CblasTrans, num, channels_, 1.,
            num_by_chans_.gpu_data(), batch_sum_multiplier_.gpu_data(), 0.,
            variance_.mutable_gpu_data());  // E((X_EX)^2)

        // compute and save moving average
        this->blobs_[2]->mutable_cpu_data()[0] *= moving_average_fraction_;
        this->blobs_[2]->mutable_cpu_data()[0] += 1;
        caffe_gpu_axpby(mean_.count(), Dtype(1), mean_.gpu_data(),
            moving_average_fraction_, this->blobs_[0]->mutable_gpu_data());
        int m = bottom[0]->count()/channels_;
        Dtype bias_correction_factor = m > 1 ? Dtype(m)/(m-1) : 1;
        caffe_gpu_axpby(variance_.count(), bias_correction_factor,
            variance_.gpu_data(), moving_average_fraction_,
            this->blobs_[1]->mutable_gpu_data());
    }
    // normalize variance
    caffe_gpu_add_scalar(variance_.count(), eps_, variance_.mutable_gpu_data());
    caffe_gpu_powx(variance_.count(), variance_.gpu_data(), Dtype(0.5),
        variance_.mutable_gpu_data());
    // new added
    const Dtype* var_data = variance_.gpu_data();
    const Dtype* mean_data = mean_.gpu_data();
    caffe_copy(bottom[0]->count(), bottom_data, top_data);
       
    int nthreads = bottom[0]->count();
    int width = bottom[0]->width();
    int height = bottom[0]->height();
    batchNorm_forward<Dtype><<<CAFFE_GET_BLOCKS(nthreads), CAFFE_CUDA_NUM_THREADS>>>(nthreads, 
                                width, height, channels_, 
                                top_data, mean_data, var_data);
    #else
    this->Forward_cpu(bottom, top);
    #endif
    /*
    // replicate variance to input size
    caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, num, channels_, 1, 1,
        batch_sum_multiplier_.gpu_data(), variance_.gpu_data(), 0.,
        num_by_chans_.mutable_gpu_data());
    caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, channels_ * num,
        spatial_dim, 1, 1., num_by_chans_.gpu_data(),
        spatial_sum_multiplier_.gpu_data(), 0., temp_.mutable_gpu_data());
    caffe_gpu_div(temp_.count(), top_data, temp_.gpu_data(), top_data);
    */
    // TODO(cdoersch): The caching is only needed because later in-place layers
    // might clobber the data.  Can we skip this if they won't?
    // caffe_copy(x_norm_.count(), top_data, x_norm_.mutable_gpu_data());
}

template <typename Dtype>
__global__ void batchNorm_backward(int nthreads, int width, int height, int channels, 
                                  Dtype* top_data, const Dtype* var_data){
    CUDA_KERNEL_LOOP(index, nthreads){
        const int fc = (index / width / height) % channels;
        const Dtype var = Dtype(1 / var_data[fc]);
        top_data[index] = Dtype(top_data[index] * var);
    }
}

template <typename Dtype>
void BatchNormLayer<Dtype>::Backward_gpu(const vector<Blob<Dtype>*>& top,
    const vector<bool>& propagate_down,
    const vector<Blob<Dtype>*>& bottom) {
    #if 1
    const Dtype* top_diff;
    if (bottom[0] != top[0]) {
        top_diff = top[0]->gpu_diff();
    } else {
        //caffe_copy(top[0]->count(), top[0]->gpu_diff(),top[0]->mutable_gpu_diff()); // top[0]->x_norm_., 前两个
        caffe_gpu_set(top[0]->count(), Dtype(0.), top[0]->mutable_gpu_diff());// new added
        top_diff = top[0]->gpu_diff(); // top[0]->x_norm_.
    }
    Dtype* bottom_diff = bottom[0]->mutable_gpu_diff();

    const Dtype* top_data = top[0]->gpu_data(); // top[0]->x_norm_.
    int num = bottom[0]->shape()[0];
    int spatial_dim = bottom[0]->count()/(channels_*bottom[0]->shape(0));
    const Dtype* var_data = variance_.gpu_data();

    //New added
    int nthreads = bottom[0]->count();
    int width = bottom[0]->width();
    int height = bottom[0]->height();
    if (use_global_stats_) {
        //caffe_gpu_div(temp_.count(), top_diff, temp_.gpu_data(), bottom_diff);
        //new added
        caffe_copy(top[0]->count(), top_diff, bottom_diff);
        batchNorm_backward<Dtype><<<CAFFE_GET_BLOCKS(nthreads), CAFFE_CUDA_NUM_THREADS>>>(nthreads, 
            width, height, channels_, bottom_diff, var_data);
        return;
    }
  
    // if Y = (X-mean(X))/(sqrt(var(X)+eps)), then
    //
    // dE(Y)/dX =
    //   (dE/dY - mean(dE/dY) - mean(dE/dY \cdot Y) \cdot Y)
    //     ./ sqrt(var(X) + eps)
    //
    // where \cdot and ./ are hadamard product and elementwise division,
    // respectively, dE/dY is the top diff, and mean/var/sum are all computed
    // along all dimensions except the channels dimension.  In the above
    // equation, the operations allow for expansion (i.e. broadcast) along all
    // dimensions except the channels dimension where required.

    // sum(dE/dY \cdot Y)
    caffe_gpu_mul(top[0]->count(), top_data, top_diff, bottom_diff); // top[0]-> temp_
    caffe_gpu_gemv<Dtype>(CblasNoTrans, channels_ * num, spatial_dim, 1.,
        bottom_diff, spatial_sum_multiplier_.gpu_data(), 0.,
        num_by_chans_.mutable_gpu_data());
    caffe_gpu_gemv<Dtype>(CblasTrans, num, channels_, 1.,
        num_by_chans_.gpu_data(), batch_sum_multiplier_.gpu_data(), 0.,
        mean_.mutable_gpu_data());

    // reshape (broadcast) the above
    caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, num, channels_, 1, 1,
        batch_sum_multiplier_.gpu_data(), mean_.gpu_data(), 0.,
        num_by_chans_.mutable_gpu_data());
    caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, channels_ * num,
        spatial_dim, 1, 1., num_by_chans_.gpu_data(),
        spatial_sum_multiplier_.gpu_data(), 0., bottom_diff);

    // sum(dE/dY \cdot Y) \cdot Y
    caffe_gpu_mul(top[0]->count(), top_data, bottom_diff, bottom_diff); // top[0]-> temp_

    // sum(dE/dY)-sum(dE/dY \cdot Y) \cdot Y
    caffe_gpu_gemv<Dtype>(CblasNoTrans, channels_ * num, spatial_dim, 1.,
        top_diff, spatial_sum_multiplier_.gpu_data(), 0.,
        num_by_chans_.mutable_gpu_data());
    caffe_gpu_gemv<Dtype>(CblasTrans, num, channels_, 1.,
        num_by_chans_.gpu_data(), batch_sum_multiplier_.gpu_data(), 0.,
        mean_.mutable_gpu_data());
    // reshape (broadcast) the above to make
    // sum(dE/dY)-sum(dE/dY \cdot Y) \cdot Y
    caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, num, channels_, 1, 1,
        batch_sum_multiplier_.gpu_data(), mean_.gpu_data(), 0.,
        num_by_chans_.mutable_gpu_data());
    caffe_gpu_gemm<Dtype>(CblasNoTrans, CblasNoTrans, num * channels_,
        spatial_dim, 1, 1., num_by_chans_.gpu_data(),
        spatial_sum_multiplier_.gpu_data(), 1., bottom_diff);

    // dE/dY - mean(dE/dY)-mean(dE/dY \cdot Y) \cdot Y
    caffe_gpu_axpby(top[0]->count(), Dtype(1), top_diff, Dtype(-1. / (num * spatial_dim)), bottom_diff); // top[0]-> temp_

    // note: temp_ still contains sqrt(var(X)+eps), computed during the forward
    // pass.
    // caffe_gpu_div(temp_.count(), bottom_diff, temp_.gpu_data(), bottom_diff);

    // new add
    batchNorm_backward<Dtype><<<CAFFE_GET_BLOCKS(nthreads), CAFFE_CUDA_NUM_THREADS>>>(nthreads, 
                    width, height, channels_, bottom_diff, var_data);
    #else
    this->Backward_cpu(top, propagate_down, bottom);
    #endif
}

INSTANTIATE_LAYER_GPU_FUNCS(BatchNormLayer);

}  // namespace caffe
