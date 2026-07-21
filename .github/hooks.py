import sys, os

def patch_file(filepath, operations):
    try:
        with open(filepath) as f:
            lines = f.readlines()
    except FileNotFoundError:
        print(f'SKIP: {filepath} not found')
        return False
    modified = False
    for op_type, target_substr, payload_lines in operations:
        if op_type in ('before', 'after'):
            found = False
            for i, line in enumerate(lines):
                if target_substr in line:
                    insert_idx = i if op_type == 'before' else i + 1
                    for j, pline in enumerate(payload_lines):
                        lines.insert(insert_idx + j, pline + '\n')
                    modified = True
                    found = True
                    break
            if not found:
                print(f'  WARN: target "{target_substr[:60]}" not found in {filepath}')
    if modified:
        with open(filepath, 'w') as f:
            f.writelines(lines)
        print(f'  OK: {filepath}')
    else:
        print(f'  SKIP: {filepath} (no changes)')
    return modified

# 1. fs/stat.c - hook newfstatat (unchanged)
patch_file('fs/stat.c', [
    ('before', '#if !defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_SYS_NEWFSTATAT)',
     ['#ifdef CONFIG_KSU_MANUAL_HOOK',
      '__attribute__((hot))',
      'extern int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags);',
      '',
      'extern void ksu_handle_newfstat_ret(unsigned int *fd, struct stat __user **statbuf_ptr);',
      '#endif',
      '']),
    ('before', '\terror = vfs_fstatat(dfd, filename, &stat, flag);',
     ['#ifdef CONFIG_KSU_MANUAL_HOOK',
      '\tksu_handle_stat(&dfd, &filename, &flag);',
      '#endif']),
])

# 2. fs/exec.c - hook do_execve (FIXED: insert before return, not after argv)
patch_file('fs/exec.c', [
    ('before', 'int do_execve(struct filename *filename,',
     ['#ifdef CONFIG_KSU_MANUAL_HOOK',
      '__attribute__((hot))',
      'extern int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags);',
      '#endif',
      '']),
    ('before', '\treturn do_execveat_common(AT_FDCWD, filename, argv, envp, 0);',
     ['#ifdef CONFIG_KSU_MANUAL_HOOK',
      '\tksu_handle_execveat((int *)AT_FDCWD, &filename, &argv, &envp, 0);',
      '#endif']),
])

# 3. fs/open.c - hook faccessat (FIXED: 4.19- kernel, hook inside faccessat)
patch_file('fs/open.c', [
    ('before', 'SYSCALL_DEFINE3(faccessat, int, dfd, const char __user *, filename, int, mode)',
     ['#ifdef CONFIG_KSU_MANUAL_HOOK',
      '__attribute__((hot))',
      'extern int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags);',
      '#endif',
      '']),
    ('before', '\tif (mode & ~S_IRWXO)',
     ['#ifdef CONFIG_KSU_MANUAL_HOOK',
      '\tksu_handle_faccessat(&dfd, &filename, &mode, NULL);',
      '#endif',
      '']),
])

# 4. kernel/reboot.c - hook sys_reboot (unchanged)
patch_file('kernel/reboot.c', [
    ('before', 'SYSCALL_DEFINE4(reboot, int, magic1, int, magic2, unsigned int, cmd,',
     ['#ifdef CONFIG_KSU_MANUAL_HOOK',
      'extern int ksu_handle_sys_reboot(int, int, unsigned int, void __user **);',
      '#endif',
      '']),
    ('after', '\tstruct pid_namespace *pid_ns = task_active_pid_ns(current);',
     ['#ifdef CONFIG_KSU_MANUAL_HOOK',
      '\tksu_handle_sys_reboot(magic1, magic2, cmd, &arg);',
      '#endif']),
])

print('=== Done ===')
