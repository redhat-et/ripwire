package enlist

type Task struct{ Do func() }

var tasks []Task

func Enlist(fn func()) { tasks = append(tasks, Task{Do: fn}) }

func realFn() {}

func init() { Enlist(realFn) }

func execTasks() {
	for _, t := range tasks {
		t.Do()
	}
}
