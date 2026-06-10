package main

import "example.com/goobjtoolexec/dep"

func main() {
	println(dep.Answer())
	println(dep.Add(20, 22))
	sum, delta := dep.Pair(10, 50)
	println(sum, delta)
	println(dep.FloatAsInt(1.25, 2.75))
	println(dep.StackAdd(100, 23))
}
