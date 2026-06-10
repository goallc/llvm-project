target triple = "x86_64-unknown-linux-goobj"

define goabiinternal i64 @"example.com/goobjtoolexec/dep.Answer"() {
entry:
  ret i64 123
}

define goabiinternal i64 @"example.com/goobjtoolexec/dep.Add"(i64 %a, i64 %b) {
entry:
  %sum = add i64 %a, %b
  ret i64 %sum
}

define goabiinternal { i64, i64 } @"example.com/goobjtoolexec/dep.Pair"(i64 %a, i64 %b) #0 {
entry:
  %sum = add i64 %a, %b
  %delta = sub i64 %b, %a
  %ret0 = insertvalue { i64, i64 } poison, i64 %sum, 0
  %ret1 = insertvalue { i64, i64 } %ret0, i64 %delta, 1
  ret { i64, i64 } %ret1
}

define goabiinternal i64 @"example.com/goobjtoolexec/dep.FloatAsInt"(double %a, double %b) {
entry:
  %sum = fadd double %a, %b
  %ret = fptosi double %sum to i64
  ret i64 %ret
}

define goabi0 i64 @"example.com/goobjtoolexec/dep.StackAdd"(i64 %a, i64 %b) {
entry:
  %sum = add i64 %a, %b
  ret i64 %sum
}

attributes #0 = { "go_results_tuple" }
