//! Compile for sparc64-linux with -fno-llvm. Each `else` body is another `if`, so the
//! backend's `airCondBr` recurses while holding a pointer into its branch stack, and
//! the nested calls grow that stack.
export fn f(a: u32) u32 {
    if (a == 0) {
        return 0;
    } else if (a == 1) {
        return 3;
    } else if (a == 2) {
        return 6;
    } else if (a == 3) {
        return 9;
    } else if (a == 4) {
        return 12;
    } else if (a == 5) {
        return 15;
    } else if (a == 6) {
        return 18;
    } else if (a == 7) {
        return 21;
    } else if (a == 8) {
        return 24;
    } else if (a == 9) {
        return 27;
    } else if (a == 10) {
        return 30;
    } else if (a == 11) {
        return 33;
    } else if (a == 12) {
        return 36;
    } else if (a == 13) {
        return 39;
    } else if (a == 14) {
        return 42;
    } else if (a == 15) {
        return 45;
    } else if (a == 16) {
        return 48;
    } else if (a == 17) {
        return 51;
    } else if (a == 18) {
        return 54;
    } else if (a == 19) {
        return 57;
    } else if (a == 20) {
        return 60;
    } else if (a == 21) {
        return 63;
    } else if (a == 22) {
        return 66;
    } else if (a == 23) {
        return 69;
    } else if (a == 24) {
        return 72;
    } else if (a == 25) {
        return 75;
    } else if (a == 26) {
        return 78;
    } else if (a == 27) {
        return 81;
    } else if (a == 28) {
        return 84;
    } else if (a == 29) {
        return 87;
    } else if (a == 30) {
        return 90;
    } else if (a == 31) {
        return 93;
    } else if (a == 32) {
        return 96;
    } else if (a == 33) {
        return 99;
    } else if (a == 34) {
        return 102;
    } else if (a == 35) {
        return 105;
    } else if (a == 36) {
        return 108;
    } else if (a == 37) {
        return 111;
    } else if (a == 38) {
        return 114;
    } else if (a == 39) {
        return 117;
    } else {
        return 999;
    }
}
