#!/usr/bin/env bash
# 测试辅助:断言 + 隔离环境 + 假 claude 桩
TESTS_RUN=0
TESTS_FAIL=0
CCM_BIN=""        # 由 test_ccm.sh 设置为 ccm 的绝对路径
SANDBOX=""        # 临时 CCM_HOME
STUBDIR=""        # 假 claude 所在目录

setup() {
  SANDBOX="$(mktemp -d)"
  STUBDIR="$(mktemp -d)"
  cat >"$STUBDIR/claude" <<'STUB'
#!/usr/bin/env bash
# 假 claude:把关心的 env 和 argv 写到 CLAUDE_STUB_OUT
{
  echo "OPUS=$ANTHROPIC_DEFAULT_OPUS_MODEL"
  echo "OPUS_NAME=$ANTHROPIC_DEFAULT_OPUS_MODEL_NAME"
  echo "SONNET=$ANTHROPIC_DEFAULT_SONNET_MODEL"
  echo "HAIKU=$ANTHROPIC_DEFAULT_HAIKU_MODEL"
  echo "SUBAGENT=$CLAUDE_CODE_SUBAGENT_MODEL"
  echo "TOKEN=$ANTHROPIC_AUTH_TOKEN"
  echo "BASE=$ANTHROPIC_BASE_URL"
  echo "ARGV=$*"
} >"${CLAUDE_STUB_OUT:-/dev/null}"
STUB
  chmod +x "$STUBDIR/claude"
}

teardown() { rm -rf "$SANDBOX" "$STUBDIR"; }

# 在隔离环境里跑 ccm:CCM_HOME=sandbox,PATH 前置桩目录
run_ccm() {
  CCM_HOME="$SANDBOX" PATH="$STUBDIR:$PATH" EDITOR=true bash "$CCM_BIN" "$@"
}

assert_eq() { # assert_eq <名称> <期望> <实际>
  TESTS_RUN=$((TESTS_RUN+1))
  if [ "$2" = "$3" ]; then
    echo "ok   - $1"
  else
    TESTS_FAIL=$((TESTS_FAIL+1))
    echo "FAIL - $1"
    echo "      expected: [$2]"
    echo "      actual:   [$3]"
  fi
}

assert_contains() { # assert_contains <名称> <子串> <文本>
  TESTS_RUN=$((TESTS_RUN+1))
  case "$3" in
    *"$2"*) echo "ok   - $1" ;;
    *) TESTS_FAIL=$((TESTS_FAIL+1)); echo "FAIL - $1"; echo "      want substr: [$2]"; echo "      in: [$3]" ;;
  esac
}

finish() {
  echo "----"
  echo "$TESTS_RUN run, $TESTS_FAIL failed"
  [ "$TESTS_FAIL" -eq 0 ]
}
