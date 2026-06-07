require 'xcodeproj'

project_path = 'VoiceTyper.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Find target
target = project.targets.find { |t| t.name == 'VoiceTyper' }

# Change product dependency to 'whisper' and 'whisper.cpp' if needed
package_deps = target.package_product_dependencies
package_deps.each do |dep|
  puts "Found product dependency: #{dep.product_name}"
end
