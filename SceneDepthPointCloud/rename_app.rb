require 'xcodeproj'

project_path = '../SceneDepthPointCloud.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  target.build_configurations.each do |config|
    if config.build_settings['PRODUCT_NAME'] == 'Point Cloud' || config.build_settings['PRODUCT_NAME'] == '"Point Cloud"'
      config.build_settings['PRODUCT_NAME'] = 'CliniBoss'
    end
  end
end

project.save
puts "Successfully renamed PRODUCT_NAME to CliniBoss."
