gke-auth() {
    region="us-central1-a"
    creds_file="creds.json"
    project_id=$(jq -r ".project_id" "$creds_file")


    # Parse flags
    while [[ $# -gt 0 ]]; do
      key="$1"
      case $key in
        (-r|--region)
          region="$2"
          shift
          shift
          ;;
        (-c|--creds_file)
          creds_file="$2"
          shift
          shift
          ;;
        (--help)
          echo "Usage: gke-auth [options]"
          echo ""
          echo "Options:"
          echo "  -r, --region VALUE    Set the region of the cluster (default: us-central1-a, remove the '-a' if zonal is set to false)"
          echo "  -c, --creds_file VALUE    Set the name of your creds file (default: creds.json)"
          echo "  --help              Show this help message and exit"
          return
          ;;
        (*)
          echo "Unknown option: $key"
          echo "Run 'gke-auth --help' for usage information."
          return
          ;;
      esac
    done

    gcloud auth activate-service-account --key-file=$creds_file

    export USE_GKE_GCLOUD_AUTH_PLUGIN=True 

    gcloud container clusters get-credentials gke \
        --region $region \
        --project $project_id

}
