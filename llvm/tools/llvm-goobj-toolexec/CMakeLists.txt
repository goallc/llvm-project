set(LLVM_LINK_COMPONENTS
  AllTargetsAsmParsers
  AllTargetsCodeGens
  AllTargetsDescs
  AllTargetsInfos
  Analysis
  AsmPrinter
  CodeGen
  Core
  IRReader
  MC
  Passes
  SelectionDAG
  Support
  Target
  TargetParser
  TransformUtils
  )

add_llvm_tool(llvm-goobj-toolexec
  llvm-goobj-toolexec.cpp

  DEPENDS
  intrinsics_gen
  )
