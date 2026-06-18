require 'xcodeproj'

project_path = '../SceneDepthPointCloud.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# 1. Files we want to MANAGE
files_to_sync = [
  'PointCloudApp.swift', 
  'HomeView.swift', 
  'CaptureView.swift', 
  'ReconstructionView.swift',
  'ExperimentalCaptureView.swift',
  'ExperimentalReconstructionView.swift',
  'ScannerSessionManager.swift',
  'QuickLookPreview.swift',
  'TrueDepthFaceView.swift',
  'AppDelegate.swift',
  'NotificationService.swift',
  'PushRegistrationService.swift'
]

# 2. Files to PURGE (deleted from project)
files_to_purge = ['PairingView.swift']

# 3. PURGE ALL REFERENCES
project.files.each do |file_ref|
  name = file_ref.name || file_ref.path
  if files_to_sync.include?(name) || files_to_purge.include?(name)
    puts "Purging global file reference: #{name} (ID: #{file_ref.uuid})"
    # Remove from all build phases first
    project.targets.each do |t|
      t.build_phases.each do |phase|
        phase.files.each do |build_file|
          if build_file.file_ref && build_file.file_ref.uuid == file_ref.uuid
            phase.remove_build_file(build_file)
          end
        end
      end
    end
    # Remove the file reference itself
    file_ref.remove_from_project
  end
end

# 4. Find the designated source group (must contain Renderer.swift)
source_file = project.files.find { |f| f.path == 'Renderer.swift' }
if source_file.nil?
  puts "ERROR: Could not find Renderer.swift to anchor the project structure."
  exit 1
end

primary_group = source_file.parent
puts "Syncing files to primary group: #{primary_group.display_name}"

# 5. Add managed files correctly
files_to_sync.each do |file|
  file_ref = primary_group.new_reference(file)
  target.add_file_references([file_ref])
  puts "Added CLEAN reference for #{file}"
end

project.save
puts "Deep Clean and Sync completed successfully."
