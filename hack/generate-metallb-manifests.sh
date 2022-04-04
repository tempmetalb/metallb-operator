#!/bin/bash
. $(dirname "$0")/common.sh

METALLB_COMMIT_ID="22491951463ae240cb7acb8a1ffd665509fa6b36"
METALLB_SC_FILE=$(dirname "$0")/securityContext.yaml

NATIVE_MANIFESTS_FILE="metallb-native.yaml"
NATIVE_MANIFESTS_URL="https://raw.githubusercontent.com/fedepaol/metallb/${METALLB_COMMIT_ID}/config/manifests/${NATIVE_MANIFESTS_FILE}"
NATIVE_MANIFESTS_DIR="bindata/deployment/native"

NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE="metallb-native-with-webhooks.yaml"
NATIVE_WITH_WEBHOOKS_MANIFESTS_URL="https://raw.githubusercontent.com/fedepaol/metallb/${METALLB_COMMIT_ID}/config/manifests/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}"
NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR="bindata/deployment/native-with-webhooks"

FRR_MANIFESTS_FILE="metallb-frr.yaml"
FRR_MANIFESTS_URL="https://raw.githubusercontent.com/fedepaol/metallb/${METALLB_COMMIT_ID}/config/manifests/${FRR_MANIFESTS_FILE}"
FRR_MANIFESTS_DIR="bindata/deployment/frr"

FRR_WITH_WEBHOOKS_MANIFESTS_FILE="metallb-frr-with-webhooks.yaml"
FRR_WITH_WEBHOOKS_MANIFESTS_URL="https://raw.githubusercontent.com/fedepaol/metallb/${METALLB_COMMIT_ID}/config/manifests/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}"
FRR_WITH_WEBHOOKS_MANIFESTS_DIR="bindata/deployment/frr-with-webhooks"

PROMETHEUS_OPERATOR_FILE="prometheus-operator.yaml"
PROMETHEUS_OPERATOR_MANIFESTS_URL="https://raw.githubusercontent.com/metallb/metallb/${METALLB_COMMIT_ID}/config/prometheus/${PROMETHEUS_OPERATOR_FILE}"
PROMETHEUS_OPERATOR_MANIFESTS_DIR="bindata/deployment/prometheus-operator"

if ! command -v yq &> /dev/null
then
    echo "yq binary not found, installing... "
    go install -mod='' github.com/mikefarah/yq/v4@v4.13.3
fi

curl ${NATIVE_MANIFESTS_URL} -o _cache/${NATIVE_MANIFESTS_FILE}

# Generate metallb rbac manifests
yq e '. | select(.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount")' _cache/${NATIVE_MANIFESTS_FILE} > config/metallb_rbac/${NATIVE_MANIFESTS_FILE}

# Generate metallb deployment manifests
yq e '. | select((.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount" or .kind == "CustomResourceDefinition" or .kind == "Namespace") | not)' _cache/${NATIVE_MANIFESTS_FILE} > ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE}

# Editing manifests to include templated variables
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.containers[0].image|="{{.ControllerImage}}"' ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.containers[0].command|= ["/controller"]' ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "DaemonSet" and .metadata.name == "speaker" and .spec.template.spec.containers[0].name == "speaker").spec.template.spec.containers[0].image|="{{.SpeakerImage}}"' ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "DaemonSet" and .metadata.name == "speaker" and .spec.template.spec.containers[0].name == "speaker").spec.template.spec.containers[0].command|= ["/speaker"]' ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE}
yq e --inplace '. | select(.metadata.namespace == "metallb-system").metadata.namespace|="{{.NameSpace}}"' ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE}
# The next part is a bit ugly because we add the sc file content as the securityContext field.
# The problem with it is that the content is added as a string and not as yaml fields, so we need to use sed to remove yaml's "|-"" mark for them to count as fields.
# Furthermore, the sed has to be last since it breaks the yaml's syntax by adding the conditionals between
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.securityContext|="'"$(< ${METALLB_SC_FILE})"'"' ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE}
sed -i 's/securityContext\: |-/securityContext\:/g' ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE} # Last because it breaks yaml syntax
sed -i 's/--log-level=info/--log-level={{.LogLevel}}/' ${NATIVE_MANIFESTS_DIR}/${NATIVE_MANIFESTS_FILE}

curl ${NATIVE_WITH_WEBHOOKS_MANIFESTS_URL} -o _cache/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}

# Generate metallb rbac manifests with webhooks configuration
yq e '. | select(.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount")' _cache/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE} > config/metallb_rbac/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}

# Generate metallb deployment manifests with webhooks configuration
yq e '. | select((.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount" or .kind == "CustomResourceDefinition" or .kind == "Namespace") | not)' _cache/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE} > ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}

# Editing metallb webhook manifests to include templated variables
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.containers[0].image|="{{.ControllerImage}}"' ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.containers[0].command|= ["/controller"]' ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "DaemonSet" and .metadata.name == "speaker" and .spec.template.spec.containers[0].name == "speaker").spec.template.spec.containers[0].image|="{{.SpeakerImage}}"' ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "DaemonSet" and .metadata.name == "speaker" and .spec.template.spec.containers[0].name == "speaker").spec.template.spec.containers[0].command|= ["/speaker"]' ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | select(.metadata.namespace == "metallb-system").metadata.namespace|="{{.NameSpace}}"' ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}
# The next part is a bit ugly because we add the sc file content as the securityContext field.
# The problem with it is that the content is added as a string and not as yaml fields, so we need to use sed to remove yaml's "|-"" mark for them to count as fields.
# Furthermore, the sed has to be last since it breaks the yaml's syntax by adding the conditionals between
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.securityContext|="'"$(< ${METALLB_SC_FILE})"'"' ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}
sed -i 's/securityContext\: |-/securityContext\:/g' ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE} # Last because it breaks yaml syntax
sed -i 's/--log-level=info/--log-level={{.LogLevel}}/' ${NATIVE_WITH_WEBHOOKS_MANIFESTS_DIR}/${NATIVE_WITH_WEBHOOKS_MANIFESTS_FILE}

curl ${FRR_MANIFESTS_URL} -o _cache/${FRR_MANIFESTS_FILE}

# Generate metallb-frr rbac manifests
yq e '. | select(.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount")' _cache/${FRR_MANIFESTS_FILE} > config/metallb_rbac/${FRR_MANIFESTS_FILE}

# Generate metallb-frr deployment manifests
yq e '. | select((.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount" or .kind == "CustomResourceDefinition"  or .kind == "Namespace") | not)' _cache/${FRR_MANIFESTS_FILE} > ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}

# Editing metallb-frr manifests to include templated variables
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.containers[0].image|="{{.ControllerImage}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.containers[0].command|= ["/controller"]' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "speaker").image)|="{{.SpeakerImage}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "speaker").command)|= ["/speaker"]' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "frr").image)|="{{.FRRImage}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "reloader").image)|="{{.FRRImage}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "frr-metrics").image)|="{{.FRRImage}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.initContainers[] | select(.name == "cp-frr-files").image)|="{{.FRRImage}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.initContainers[] | select(.name == "cp-reloader").image)|="{{.SpeakerImage}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.initContainers[] | select(.name == "cp-metrics").image)|="{{.SpeakerImage}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller" and .spec.template.spec.securityContext.runAsUser == "65534").spec.template.spec.securityContext|="'"$(< ${METALLB_SC_FILE})"'"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
yq e --inplace '. | select(.metadata.namespace == "metallb-system").metadata.namespace|="{{.NameSpace}}"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
sed -i 's/--log-level=info/--log-level={{.LogLevel}}/' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
sed -i '/- name: FRR_LOGGING_LEVEL/ s//# &/' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
sed -i '/  value: informational/ s//# &/' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}

# The next part is a bit ugly because we add the sc file content as the securityContext field.
# The problem with it is that the content is added as a string and not as yaml fields, so we need to use sed to remove yaml's "|-"" mark for them to count as fields.
# Furthermore, the sed has to be last since it breaks the yaml's syntax by adding the conditionals between
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.securityContext|="'"$(< ${METALLB_SC_FILE})"'"' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
# Last because they break yaml syntax
sed -i 's/securityContext\: |-/securityContext\:/g' ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
sed -i "s/- name: '{{ if .DeployKubeRbacProxies }}'/{{ if .DeployKubeRbacProxies }}/g" ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}
sed -i "s/- name: '{{ end }}'/{{ end }}/g" ${FRR_MANIFESTS_DIR}/${FRR_MANIFESTS_FILE}

curl ${FRR_WITH_WEBHOOKS_MANIFESTS_URL} -o _cache/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}

# Generate metallb-frr rbac manifests with webhook configuration
yq e '. | select(.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount")' _cache/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE} > config/metallb_rbac/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}

# Generate metallb-frr deployment manifests with webhook configuration
yq e '. | select((.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount" or .kind == "CustomResourceDefinition"  or .kind == "Namespace") | not)' _cache/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE} > ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}

# Editing metallb-frr webhook manifests to include templated variables
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.containers[0].image|="{{.ControllerImage}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.containers[0].command|= ["/controller"]' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "speaker").image)|="{{.SpeakerImage}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "speaker").command)|= ["/speaker"]' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "frr").image)|="{{.FRRImage}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "reloader").image)|="{{.FRRImage}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.containers[] | select(.name == "frr-metrics").image)|="{{.FRRImage}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.initContainers[] | select(.name == "cp-frr-files").image)|="{{.FRRImage}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.initContainers[] | select(.name == "cp-reloader").image)|="{{.SpeakerImage}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | (select(.kind == "DaemonSet" and .metadata.name == "speaker") | .spec.template.spec.initContainers[] | select(.name == "cp-metrics").image)|="{{.SpeakerImage}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller" and .spec.template.spec.securityContext.runAsUser == "65534").spec.template.spec.securityContext|="'"$(< ${METALLB_SC_FILE})"'"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
yq e --inplace '. | select(.metadata.namespace == "metallb-system").metadata.namespace|="{{.NameSpace}}"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
sed -i 's/--log-level=info/--log-level={{.LogLevel}}/' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
sed -i '/- name: FRR_LOGGING_LEVEL/ s//# &/' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
sed -i '/  value: informational/ s//# &/' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}

# The next part is a bit ugly because we add the sc file content as the securityContext field.
# The problem with it is that the content is added as a string and not as yaml fields, so we need to use sed to remove yaml's "|-"" mark for them to count as fields.
# Furthermore, the sed has to be last since it breaks the yaml's syntax by adding the conditionals between
yq e --inplace '. | select(.kind == "Deployment" and .metadata.name == "controller" and .spec.template.spec.containers[0].name == "controller").spec.template.spec.securityContext|="'"$(< ${METALLB_SC_FILE})"'"' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
# Last because they break yaml syntax
sed -i 's/securityContext\: |-/securityContext\:/g' ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
sed -i "s/- name: '{{ if .DeployKubeRbacProxies }}'/{{ if .DeployKubeRbacProxies }}/g" ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}
sed -i "s/- name: '{{ end }}'/{{ end }}/g" ${FRR_WITH_WEBHOOKS_MANIFESTS_DIR}/${FRR_WITH_WEBHOOKS_MANIFESTS_FILE}

# Update MetalLB's E2E lane to clone the same commit as the manifests.
yq e --inplace ".jobs.main.steps[] |= select(.name==\"Checkout MetalLB\").with.ref=\"${METALLB_COMMIT_ID}\"" .github/workflows/metallb_e2e.yml

# TODO: run this script once FRR is merged

# Prometheus Operator manifests
curl ${PROMETHEUS_OPERATOR_MANIFESTS_URL} -o _cache/${PROMETHEUS_OPERATOR_FILE}
yq e '. | select((.kind == "Role" or .kind == "ClusterRole" or .kind == "RoleBinding" or .kind == "ClusterRoleBinding" or .kind == "ServiceAccount") | not)' _cache/${PROMETHEUS_OPERATOR_FILE} > ${PROMETHEUS_OPERATOR_MANIFESTS_DIR}/${PROMETHEUS_OPERATOR_FILE}
yq e --inplace '. | select(.kind == "PodMonitor").metadata.namespace|="{{.NameSpace}}"' ${PROMETHEUS_OPERATOR_MANIFESTS_DIR}/${PROMETHEUS_OPERATOR_FILE}
yq e --inplace '. | select(.kind == "PodMonitor").spec.namespaceSelector.matchNames|=["{{.NameSpace}}"]' ${PROMETHEUS_OPERATOR_MANIFESTS_DIR}/${PROMETHEUS_OPERATOR_FILE}
