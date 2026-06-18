require 'xcodeproj'
project_path = '../SceneDepthPointCloud.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first
group = project.main_group['SceneDepthPointCloud'] || project.main_group

files = ['ModelCropper.swift']
files.each do |file_name|
  file_ref = group.find_file_by_path(file_name) || group.new_file(file_name)
  target.add_file_references([file_ref])
end

project.save
puts "Added ModelCropper.swift to target."
