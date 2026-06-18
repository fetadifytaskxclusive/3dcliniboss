require 'xcodeproj'
project = Xcodeproj::Project.open('../SceneDepthPointCloud.xcodeproj')
target = project.targets.first
keep = ['PointCloudApp.swift', 'HomeView.swift', 'CaptureView.swift', 'ReconstructionView.swift']

puts "Files in source build phase:"
target.source_build_phase.files.to_a.each do |f|
  if f.file_ref
    fname = f.file_ref.name || f.file_ref.path
    if fname
      puts "- #{fname}"
      if !keep.include?(fname)
        puts "  -> Removing #{fname}"
        f.remove_from_project
      end
    end
  end
end

project.save
puts "Done pruning."
