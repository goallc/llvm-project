target triple = "x86_64-unknown-linux-goobj"

%go.rtype = type { i64, i64, i32, i8, i8, i8, i8, ptr, ptr, i32, i32 }
%go.uncommon = type { i32, i16, i16, i32, i32 }
%go.struct.field = type { ptr, ptr, i64 }
%go.method = type { i32, i32, i32, i32 }
%go.struct.type.uncommon = type { %go.rtype, ptr, ptr, i64, i64, %go.uncommon, %go.struct.field, %go.method }

@"type:int64" = external global i8
@"type:func() int64" = external global i8

@"type:.namedata.*dep.LLVMDescriptorBox." = constant [24 x i8] c"\01\16*dep.LLVMDescriptorBox", section ".rodata", align 1, !goobj.symbol.flags !1
@"type:.importpath.example.com/goobjtoolexec/dep." = constant [31 x i8] c"\00\1Dexample.com/goobjtoolexec/dep", section ".rodata", align 1, !goobj.symbol.flags !1
@"type:.namedata.V." = constant [3 x i8] c"\01\01V", section ".rodata", align 1, !goobj.symbol.flags !1
@"type:.namedata.BoxValue." = constant [10 x i8] c"\01\08BoxValue", section ".rodata", align 1, !goobj.symbol.flags !1

@"type:example.com/goobjtoolexec/dep.LLVMDescriptorBox" = constant %go.struct.type.uncommon {
  %go.rtype {
    i64 8,
    i64 0,
    i32 305419896,
    i8 15,
    i8 8,
    i8 8,
    i8 25,
    ptr null,
    ptr null,
    i32 ptrtoint (ptr @"type:.namedata.*dep.LLVMDescriptorBox." to i32),
    i32 0
  },
  ptr null,
  ptr getelementptr inbounds (%go.struct.type.uncommon, ptr @"type:example.com/goobjtoolexec/dep.LLVMDescriptorBox", i32 0, i32 6),
  i64 1,
  i64 1,
  %go.uncommon {
    i32 ptrtoint (ptr @"type:.importpath.example.com/goobjtoolexec/dep." to i32),
    i16 1,
    i16 1,
    i32 40,
    i32 0
  },
  %go.struct.field {
    ptr @"type:.namedata.V.",
    ptr @"type:int64",
    i64 0
  },
  %go.method {
    i32 ptrtoint (ptr @"type:.namedata.BoxValue." to i32),
    i32 ptrtoint (ptr @"type:func() int64" to i32),
    i32 ptrtoint (ptr @"example.com/goobjtoolexec/dep.(*LLVMDescriptorBox).BoxValue" to i32),
    i32 ptrtoint (ptr @"example.com/goobjtoolexec/dep.LLVMDescriptorBox.BoxValue" to i32)
  }
}, section ".rodata", align 8, !goobj.symbol.flags !2

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

define goabi0 i64 @"example.com/goobjtoolexec/dep.StackAdd<ABI0>"(i64 %a, i64 %b) {
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
declare goabiinternal ptr @"runtime.newobject"(ptr)

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

define goabiinternal i64 @"example.com/goobjtoolexec/dep.(*LLVMDescriptorBox).BoxValue"(ptr %recv) {
entry:
  %value = load i64, ptr %recv, align 8
  ret i64 %value
}

define goabiinternal i64 @"example.com/goobjtoolexec/dep.LLVMDescriptorBox.BoxValue"(i64 %value) {
entry:
  ret i64 %value
}

define goabiinternal { ptr, ptr } @"example.com/goobjtoolexec/dep.MakeLLVMDescriptorBox"(i64 %value) {
entry:
  %box = call goabiinternal ptr @"runtime.newobject"(ptr @"type:example.com/goobjtoolexec/dep.LLVMDescriptorBox")
  store i64 %value, ptr %box, align 8
  %ret.type = insertvalue { ptr, ptr } poison, ptr @"type:example.com/goobjtoolexec/dep.LLVMDescriptorBox", 0
  %ret.data = insertvalue { ptr, ptr } %ret.type, ptr %box, 1
  ret { ptr, ptr } %ret.data
}

attributes #0 = { "go_results_tuple" }

!1 = !{i32 1, i32 0}
!2 = !{i32 64, i32 1}
