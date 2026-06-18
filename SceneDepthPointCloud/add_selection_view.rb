require 'xcodeproj'

project_path = '../SceneDepthPointCloud.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group['SceneDepthPointCloud'] || project.main_group

file_ref = group.find_file_by_path('ScanSelectionView.swift') || group.new_file('ScanSelectionView.swift')
target.add_file_references([file_ref])

project.save
puts "Successfully added ScanSelectionView.swift to PBXProj."
