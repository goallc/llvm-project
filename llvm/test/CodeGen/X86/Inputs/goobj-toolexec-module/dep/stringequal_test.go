package dep

import (
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
