go-rebase() {
    default_branch="main"


    # Parse flags
    while [[ $# -gt 0 ]]; do
      key="$1"
      case $key in
        (-b|--default-branch)
          default_branch="$2"
          shift
          shift
          ;;
        (--help)
          echo "Usage: go-rebase [options]"
          echo ""
          echo "Options:"
          echo "  -b, --default-branch VALUE    Set the default branch to rebase from merge-base (default: main)"
          echo "  --help              Show this help message and exit"
          return
          ;;
        (*)
          echo "Unknown option: $key"
          echo "Run 'go-rebase --help' for usage information."
          return
          ;;
      esac
    done

    git rebase -i $(git merge-base $default_branch $(git rev-parse --abbrev-ref HEAD))
}
