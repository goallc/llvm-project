package dep

type descriptorBoxer interface {
	BoxValue() int64
}

var descriptorBoxerSink descriptorBoxer

func Answer() int64
func Add(a, b int64) int64
func Pair(a, b int64) (int64, int64)
func FloatAsInt(a, b float64) int64
func StackAdd(a, b int64) int64
func StringEqual(a, b string) bool
func FillStack(buf []byte) int
func TriggerGC()
func MakeLLVMDescriptorBox(v int64) any
