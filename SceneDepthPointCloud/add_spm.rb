require 'xcodeproj'

project_path = '../SceneDepthPointCloud.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Check if dependency exists, if not add it
url = 'https://github.com/magicien/GLTFSceneKit'
requirement = Xcodeproj::Project::Object::XCRemoteSwiftPackageReference::Requirement.upToNextMajorVersion('0.4.1')

# Add swift package reference
pkg_ref = project.root_object.package_references.find { |p| p.repositoryURL == url }
unless pkg_ref
  pkg_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg_ref.repositoryURL = url
  pkg_ref.requirement = requirement
  project.root_object.package_references << pkg_ref
end

# Add package to targets
project.targets.each do |target|
  # skip test targets
  next if target.name.include?("Test")
  
  # Ensure the package is a dependency
  dep = target.package_product_dependencies.find { |d| d.product_name == 'GLTFSceneKit' }
  unless dep
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.product_name = 'GLTFSceneKit'
    dep.package = pkg_ref
    target.package_product_dependencies << dep
  end
end

project.save
puts "Added GLTFSceneKit package."
