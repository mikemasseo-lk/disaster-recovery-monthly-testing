# Adding DR EKS Clusters to Kubeconfig

## Overview
This guide explains how to add Disaster Recovery (DR) environment EKS clusters to your local kubeconfig file for kubectl access.

## Prerequisites
- AWS CLI installed and configured
- AWS DR profile configured (`~/.aws/config` or `~/.aws/credentials`)
- Appropriate IAM permissions to describe EKS clusters
- kubectl installed

## DR Environment Clusters

The DR environment currently has the following EKS clusters in **us-east-2**:
- `mgmt-use2-eks-1` - Management cluster
- `prod-eks-1` - Production cluster

## Step-by-Step Instructions

### 1. Set AWS Profile to DR
```bash
export AWS_PROFILE=dr
```

### 2. Verify Available Clusters (Optional)
```bash
aws eks list-clusters --output json
```

Expected output:
```json
{
    "clusters": [
        "mgmt-use2-eks-1",
        "prod-eks-1"
    ]
}
```

### 3. Add Clusters to Kubeconfig

#### Add Management Cluster
```bash
aws eks update-kubeconfig --name mgmt-use2-eks-1 --region us-east-2
```

#### Add Production Cluster
```bash
aws eks update-kubeconfig --name prod-eks-1 --region us-east-2
```

Expected output for each command:
```
Updated context arn:aws:eks:us-east-2:051826732093:cluster/<cluster-name> in /home/<username>/.kube/config
```

### 4. Verify Cluster Access

#### List all contexts
```bash
kubectl config get-contexts
```

#### Switch to a specific cluster
```bash
kubectl config use-context arn:aws:eks:us-east-2:051826732093:cluster/mgmt-use2-eks-1
```

#### Test cluster access
```bash
kubectl get nodes
```

## Troubleshooting

### Issue: "No cluster found for name"
**Cause**: Incorrect region specified

**Solution**: Verify the region where the cluster is located:
```bash
aws eks describe-cluster --name <cluster-name> --region us-east-2
```

### Issue: "error: You must be logged in to the server (Unauthorized)"
**Cause**: IAM permissions or authentication issue

**Solution**:
1. Verify your AWS profile is set correctly: `echo $AWS_PROFILE`
2. Check your IAM role/user has EKS access permissions
3. Try re-authenticating: `aws sts get-caller-identity --profile dr`

### Issue: Cluster context not appearing
**Cause**: Kubeconfig file permissions or path issue

**Solution**:
1. Verify kubeconfig location: `echo $KUBECONFIG` (default: `~/.kube/config`)
2. Check file permissions: `ls -la ~/.kube/config`
3. Re-run the update-kubeconfig command with `--verbose` flag

## Quick Reference

### Add all DR clusters at once
```bash
export AWS_PROFILE=dr
aws eks update-kubeconfig --name mgmt-use2-eks-1 --region us-east-2
aws eks update-kubeconfig --name prod-eks-1 --region us-east-2
```

### Switch between DR clusters
```bash
# List contexts
kubectl config get-contexts

# Switch to management cluster
kubectl config use-context arn:aws:eks:us-east-2:051826732093:cluster/mgmt-use2-eks-1

# Switch to production cluster
kubectl config use-context arn:aws:eks:us-east-2:051826732093:cluster/prod-eks-1
```

## Additional Resources
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
- [kubectl Configuration Documentation](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)

## Notes
- The `aws eks update-kubeconfig` command automatically configures authentication using aws-iam-authenticator
- Context names use the full ARN format by default
- You can customize context names using the `--alias` flag: `--alias dr-prod`
