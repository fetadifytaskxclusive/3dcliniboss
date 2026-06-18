require 'xcodeproj'
project = Xcodeproj::Project.open('../SceneDepthPointCloud.xcodeproj')
pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg_ref.repositoryURL = 'https://github.com/magicien/GLTFSceneKit.git'
pkg_ref.requirement = {
  "kind" => "upToNextMajorVersion",
  "minimumVersion" => "0.4.1"
}
project.root_object.package_references << pkg_ref

project.targets.each do |target|
  dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  dep.product_name = 'GLTFSceneKit'
  dep.package = pkg_ref
  target.package_product_dependencies << dep
end

project.save
puts "Added SPM package using hash requirement"
