package pipe

import "core:log"
import "core:os"

run_command :: proc {
	run_command_pipe,
	run_command_free,
}

Pipe :: struct {
	stderr: string,
	stdout: string,
}

/*
Runs command capturing stdout and stderr

The result can be directly send to another command
*/
run_command_pipe :: proc(
	args: []string,
	pipe: ^Pipe,
	stdin := os.stdin,
	working_dir: string = "",
	env: []string = nil,
	allocator := context.allocator,
	logger := context.logger,
) -> bool {
	pd := os.Process_Desc {
		stdin       = stdin,
		command     = args,
		working_dir = working_dir,
		env         = env,
	}
	state: os.Process_State
	err: os.Error
	stdout, stderr: []byte

	if len(pipe.stdout) != 0 {
		defer delete(pipe.stdout)
		defer delete(pipe.stderr)
		state, stdout, stderr, err = os.process_exec(pd, allocator)
		if err != nil {
			log.error(os.error_string(err))
			return false
		}
	} else {
		state, stdout, stderr, err = os.process_exec(pd, allocator)
		if err != nil {
			log.error(os.error_string(err))
			return false
		}
	}

	trim :: proc(s: string) -> (res: string) #no_bounds_check {
		n := len(s)
		if n > 0 {
			if s[n - 1] == '\n' {
				return s[:n - 1]
			}
		}
		return s
	}

	pipe.stdout = trim(string(stdout))
	pipe.stderr = trim(string(stderr))

	return state.exit_code == 0
}

/*
Runs command without capturing stdout and stderr
*/
run_command_free :: proc(
	args: []string,
	stdout := os.stdout,
	stderr := os.stderr,
	stdin := os.stdin,
	working_dir: string = "",
	env: []string = nil,
) -> bool {

	pd := os.Process_Desc {
		stdin       = stdin,
		stdout      = stdout,
		stderr      = stderr,
		command     = args,
		working_dir = working_dir,
		env         = env,
	}

	process: os.Process
	state: os.Process_State
	err: os.Error

	process, err = os.process_start(pd)
	if err != nil {
		log.error(os.error_string(err))
		return false
	}
	state, err = os.process_wait(process)
	if err != nil {
		log.error(os.error_string(err))
		return false
	}

	return state.exit_code == 0
}

destroy :: proc(pipe: ^Pipe) {
	delete(pipe.stdout)
	delete(pipe.stderr)
}
