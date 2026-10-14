#
# Hunspell for the macOS build of Haruspex. The C++ sources live in ../src
# (shared with Linux). Classes/ holds one file per source that includes it,
# since a podspec cannot point outside its folder.
#
Pod::Spec.new do |s|
  s.name             = 'haruspex_hunspell'
  s.version          = '1.7.5'
  s.summary          = 'Hunspell spell checker for Haruspex.'
  s.description      = 'Hunspell 1.7.5, called from Dart through dart:ffi.'
  s.homepage         = 'https://github.com/hunspell/hunspell'
  s.license          = { :type => 'MPL-1.1 OR GPL-2.0-or-later OR LGPL-2.1-or-later' }
  s.author           = { 'Haruspex' => 'https://github.com/Vylca/haruspex' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.15'
  s.library          = 'c++'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'CLANG_CXX_LIBRARY' => 'libc++',
    # Exports the C API (Hunspell_create, Hunspell_spell...).
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) BUILDING_LIBHUNSPELL=1',
    'GCC_WARN_INHIBIT_ALL_WARNINGS' => 'YES',
  }
  s.swift_version    = '5.0'
end
