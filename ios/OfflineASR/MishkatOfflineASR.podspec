Pod::Spec.new do |s|
  s.name = 'MishkatOfflineASR'
  s.version = '1.13.8'
  s.summary = 'Pinned local Sherpa ONNX and ONNX Runtime for Mishkat recitation.'
  s.description = 'CPU speech recognition using verified static iOS libraries; assets are bundled by Runner.'
  s.homepage = 'https://github.com/k2-fsa/sherpa-onnx'
  s.license = { :type => 'Apache-2.0 AND MIT', :file => 'LICENSES.txt' }
  s.author = { 'Sherpa ONNX contributors' => 'https://github.com/k2-fsa/sherpa-onnx' }
  # CocoaPods uses this specification through :path. The preparation script
  # obtains both exact artifacts in artifacts.json before dependency resolution.
  s.source = {
    :http => 'https://github.com/k2-fsa/sherpa-onnx/releases/download/xcframework/sherpa-onnx-v1.13.8-ios-static.xcframework.zip',
    :sha256 => '6b8e769cb153343270fdccbe92e3b3db0d1c421d67fa0989ab01fdf5b2fcf2de',
  }
  s.platform = :ios, '15.0'
  s.static_framework = true
  s.vendored_frameworks = 'Vendor/SherpaOnnxC.xcframework', 'Vendor/onnxruntime.xcframework'
  s.preserve_paths = 'Vendor/**/*', 'artifacts.json', 'IOS_ENGINE_NOTICE.txt'
  s.frameworks = 'Foundation', 'CoreFoundation', 'CoreML', 'Accelerate'
  s.libraries = 'c++'
end
