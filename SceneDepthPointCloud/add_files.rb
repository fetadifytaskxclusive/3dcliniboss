require 'xcodeproj'
project_path = '../SceneDepthPointCloud.xcodeproj'
project = Xcodeproj::Project.open(project_path)

group = project.main_group['SceneDepthPointCloud']
target = project.targets.first

['AVCaptureManager.swift', 'CameraPreviewView.swift'].each do |file_name|
  # File might already be in project but not target, or not in project at all
  file_ref = group.files.find { |f| f.path == file_name }
  if !file_ref
    file_ref = group.new_file(file_name)
  end
  
  # Ensure it is in the target's source build phase
  unless target.source_build_phase.files_references.include?(file_ref)
    target.source_build_phase.add_file_reference(file_ref)
    puts "Added #{file_name} to target"
  end
end

project.save
puts "Project saved"
