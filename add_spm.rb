require 'xcodeproj'

project_path = 'VoiceTyper.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Clean up all package references
project.root_object.package_references.each do |ref|
  ref.remove_from_project
end

target = project.targets.find { |t| t.name == 'VoiceTyper' }
target.package_product_dependencies.each do |dep|
  dep.remove_from_project
end
target.frameworks_build_phase.files.each do |file|
  if file.product_ref.is_a?(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    file.remove_from_project
  end
end

repository_url = 'https://github.com/exPHAT/SwiftWhisper.git'

pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
pkg.repositoryURL = repository_url
pkg.requirement = {
  "kind" => "upToNextMajorVersion",
  "minimumVersion" => "1.0.0"
}

project.root_object.package_references << pkg

package_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
package_dep.product_name = 'SwiftWhisper'
package_dep.package = pkg

target.package_product_dependencies << package_dep

build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = package_dep
target.frameworks_build_phase.files << build_file

project.save
puts "Successfully added SwiftWhisper dependency."
