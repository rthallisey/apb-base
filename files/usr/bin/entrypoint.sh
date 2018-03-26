#!/bin/bash

set -x

# Work-Around
# The OpenShift's s2i (source to image) requires that no ENTRYPOINT exist
# for any of the s2i builder base images.  Our 's2i-apb' builder uses the
# apb-base as it's base image.  But since the apb-base defines its own
# entrypoint.sh, it is not compatible with the current source-to-image.
#
# The below work-around checks if the entrypoint was called within the
# s2i-apb's 'assemble' script process. If so, it skips the rest of the steps
# which are APB run-time specific.
#
# Details of the issue in the link below:
# https://github.com/openshift/source-to-image/issues/475
#
if [[ $@ == *"s2i/assemble"* ]]; then
  echo "---> Performing S2I build... Skipping server startup"
  exec "$@"
  exit $?
fi

ACTION=$1
shift

apb_action_path="${APB_ACTION_PATH:-}"
playbooks="/etc/ansible/roles/${apb_action_path}"

CREDS="/var/tmp/bind-creds"
TEST_RESULT="/var/tmp/test-result"

if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    echo "${USER_NAME:-apb}:x:$(id -u):0:${USER_NAME:-apb} user:${HOME}:/sbin/nologin" >> /etc/passwd
  fi
fi

set +x

SECRETS_DIR=/etc/apb-secrets
mounted_secrets=$(ls $SECRETS_DIR)

extra_args=""
if [[ ! -z "$mounted_secrets" ]] ; then

    echo '---' > /tmp/secrets

    for key in ${mounted_secrets} ; do
      for file in $(ls ${SECRETS_DIR}/${key}/..data); do
        echo "$file: $(cat ${SECRETS_DIR}/${key}/..data/${file})" >> /tmp/secrets
      done
    done
    extra_args='--extra-vars no_log=true --extra-vars @/tmp/secrets'
fi
set -x

# if [[ -e "/opt/ansible/requirements.yml" ]]; then
#   ansible-galaxy install -r /opt/ansible/requirements.yml
# elif [[ -e "/opt/ansible/requirments.yaml" ]]; then
#   ansible-galaxy install -r /opt/ansible/requirments.yaml
# fi

# $playbook is the path of the plabook to run. Pass in action=$ACTION as env var.
if [[ -e "$playbooks" && ! -d "$playbooks" ]]; then
  ANSIBLE_ROLES_PATH=/etc/ansible/roles:/opt/ansible/roles ansible-playbook $playbooks -e action=$ACTION "${@}" ${extra_args}
elif [[ -e "$playbooks/$ACTION.yaml" ]]; then
  ANSIBLE_ROLES_PATH=/etc/ansible/roles:/opt/ansible/roles ansible-playbook $playbooks/$ACTION.yaml "${@}" ${extra_args}
elif [[ -e "$playbooks/$ACTION.yml" ]]; then
  ANSIBLE_ROLES_PATH=/etc/ansible/roles:/opt/ansible/roles ansible-playbook $playbooks/$ACTION.yml  "${@}" ${extra_args}
else
  echo "'$ACTION' NOT IMPLEMENTED" # TODO
  exit 8 # action not found
fi

EXIT_CODE=$?

set +ex
rm -f /tmp/secrets
set -ex

if [ -f $TEST_RESULT ]; then
   test-retrieval-init
fi

exit $EXIT_CODE
