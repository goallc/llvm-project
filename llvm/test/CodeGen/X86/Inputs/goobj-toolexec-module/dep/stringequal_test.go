package dep

import (
	"reflect"
	"strings"
	"testing"
)

var stringEqualSink bool

var equalLeft = "the quick brown fox jumps over the lazy dog: 0123456789: abcdefghijklmnopqrstuvwxyz"
var equalRight = "the quick brown fox jumps over the lazy dog: 0123456789: abcdefghijklmnopqrstuvwxyz"
var differentRight = "the quick brown fox jumps over the lazy dog: 0123456789: abcdefghijklmnopqrstuvwxzz"
var shortRight = "the quick brown fox"

//go:noinline
func nativeStringEqual(a, b string) bool {
	return a == b
}

func TestStringEqual(t *testing.T) {
	tests := []struct {
		name string
		a    string
		b    string
		want bool
	}{
		{"empty", "", "", true},
		{"equal", equalLeft, equalRight, true},
		{"different-byte", equalLeft, differentRight, false},
		{"different-length", equalLeft, shortRight, false},
	}

	for _, tt := range tests {
		if got := StringEqual(tt.a, tt.b); got != tt.want {
			t.Fatalf("%s: StringEqual(%q, %q) = %v, want %v",
				tt.name, tt.a, tt.b, got, tt.want)
		}
	}
}

func TestLLVMRuntimeStack(t *testing.T) {
	buf := make([]byte, 4096)
	n := FillStack(buf)
	if n <= 0 {
		t.Fatalf("FillStack returned %d bytes", n)
	}

	stack := string(buf[:n])
	if !strings.Contains(stack, "example.com/goobjtoolexec/dep.FillStack") {
		t.Fatalf("runtime.Stack did not include LLVM frame; stack:\n%s", stack)
	}
	if !strings.Contains(stack, "example.com/goobjtoolexec/dep.TestLLVMRuntimeStack") {
		t.Fatalf("runtime.Stack did not include Go caller; stack:\n%s", stack)
	}
}

func TestLLVMTriggerGC(t *testing.T) {
	for i := 0; i < 3; i++ {
		_ = make([]byte, 1<<20)
		TriggerGC()
	}
}

func TestLLVMTypeDescriptor(t *testing.T) {
	value := MakeLLVMDescriptorBox(77)
	typ := reflect.TypeOf(value)
	if typ.Name() != "LLVMDescriptorBox" {
		t.Fatalf("type name = %q, want LLVMDescriptorBox", typ.Name())
	}
	if typ.PkgPath() != "example.com/goobjtoolexec/dep" {
		t.Fatalf("type package path = %q, want example.com/goobjtoolexec/dep", typ.PkgPath())
	}
	if typ.Kind() != reflect.Struct {
		t.Fatalf("type kind = %v, want struct", typ.Kind())
	}

	field, ok := typ.FieldByName("V")
	if !ok {
		t.Fatalf("LLVMDescriptorBox is missing field V")
	}
	if field.Type.Kind() != reflect.Int64 {
		t.Fatalf("field V kind = %v, want int64", field.Type.Kind())
	}

	gotField := reflect.ValueOf(value).FieldByName("V").Int()
	if gotField != 77 {
		t.Fatalf("reflected V = %d, want 77", gotField)
	}

	boxer, ok := value.(descriptorBoxer)
	if !ok {
		t.Fatalf("LLVMDescriptorBox did not satisfy descriptorBoxer")
	}
	if got := boxer.BoxValue(); got != 77 {
		t.Fatalf("BoxValue() = %d, want 77", got)
	}
}

func BenchmarkStringEqualNativeDirectEqual(b *testing.B) {
	for i := 0; i < b.N; i++ {
		stringEqualSink = equalLeft == equalRight
	}
}

func BenchmarkStringEqualNativeFuncEqual(b *testing.B) {
	for i := 0; i < b.N; i++ {
		stringEqualSink = nativeStringEqual(equalLeft, equalRight)
	}
}

func BenchmarkStringEqualLLVMEqual(b *testing.B) {
	for i := 0; i < b.N; i++ {
		stringEqualSink = StringEqual(equalLeft, equalRight)
	}
}

func BenchmarkStringEqualNativeDirectDifferent(b *testing.B) {
	for i := 0; i < b.N; i++ {
		stringEqualSink = equalLeft == differentRight
	}
}

func BenchmarkStringEqualNativeFuncDifferent(b *testing.B) {
	for i := 0; i < b.N; i++ {
		stringEqualSink = nativeStringEqual(equalLeft, differentRight)
	}
}

func BenchmarkStringEqualLLVMDifferent(b *testing.B) {
	for i := 0; i < b.N; i++ {
		stringEqualSink = StringEqual(equalLeft, differentRight)
	}
}
