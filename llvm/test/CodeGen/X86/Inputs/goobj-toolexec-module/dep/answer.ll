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

define goabiinternal i8 @"example.com/goobjtoolexec/dep.StringEqual"({ ptr, i64 } %a, { ptr, i64 } %b) {
entry:
  %aptr = extractvalue { ptr, i64 } %a, 0
  %alen = extractvalue { ptr, i64 } %a, 1
  %bptr = extractvalue { ptr, i64 } %b, 0
  %blen = extractvalue { ptr, i64 } %b, 1
  %same_len = icmp eq i64 %alen, %blen
  br i1 %same_len, label %len_equal, label %return_false

len_equal:
  %empty = icmp eq i64 %alen, 0
  br i1 %empty, label %return_true, label %loop

loop:
  %i = phi i64 [ 0, %len_equal ], [ %next, %continue ]
  %aelt = getelementptr inbounds i8, ptr %aptr, i64 %i
  %belt = getelementptr inbounds i8, ptr %bptr, i64 %i
  %abyte = load i8, ptr %aelt, align 1
  %bbyte = load i8, ptr %belt, align 1
  %same_byte = icmp eq i8 %abyte, %bbyte
  br i1 %same_byte, label %continue, label %return_false

continue:
  %next = add nuw i64 %i, 1
  %done = icmp eq i64 %next, %alen
  br i1 %done, label %return_true, label %loop

return_true:
  ret i8 1

return_false:
  ret i8 0
}

declare goabiinternal i64 @"runtime.Stack"({ ptr, i64, i64 }, i8)
declare goabiinternal void @"runtime.GC"()

define goabiinternal i64 @"example.com/goobjtoolexec/dep.FillStack"({ ptr, i64, i64 } %buf) {
entry:
  %n = call goabiinternal i64 @"runtime.Stack"({ ptr, i64, i64 } %buf, i8 0)
  ret i64 %n
}

define goabiinternal void @"example.com/goobjtoolexec/dep.TriggerGC"() {
entry:
  call goabiinternal void @"runtime.GC"()
  ret void
}

attributes #0 = { "go_results_tuple" }
