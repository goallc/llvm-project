target triple = "x86_64-unknown-linux-goobj"

define void @"example.com/goobjtoolexec/dep.Answer"() {
entry:
  call void asm sideeffect "movq $$123, 8(%rsp)", "~{memory}"()
  ret void
}
