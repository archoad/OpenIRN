# Fonctions d'authentification Kibana partagées par les scripts de déploiement.
# Ce fichier est chargé par `source` et n'est pas exécutable seul.

# Écrit dans $1 une configuration curl contenant les credentials Kibana.
# Avec $2 = rules, refuse une clé API sauf si OPENIRN_RULES_ALLOW_API_KEY=true :
# une règle créée ou modifiée avec une clé API s'exécute avec cette même clé et
# échoue dès qu'elle expire ou est invalidée.
kibana_write_auth_config() {
	local output=$1
	local purpose=${2:-objects}

	if [[ -n ${KIBANA_USERNAME:-} ]]; then
		if [[ ! ${KIBANA_USERNAME} =~ ^[A-Za-z0-9._@-]{1,255}$ ]]; then
			echo 'KIBANA_USERNAME contient un nom d’utilisateur invalide.' >&2
			return 1
		fi
		if [[ -z ${KIBANA_PASSWORD:-} ]]; then
			echo 'KIBANA_PASSWORD doit accompagner KIBANA_USERNAME.' >&2
			return 1
		fi
		local escaped=${KIBANA_PASSWORD//\\/\\\\}
		escaped=${escaped//\"/\\\"}
		(umask 077; printf 'user = "%s:%s"\n' "${KIBANA_USERNAME}" "${escaped}" > "${output}")
		KIBANA_AUTH_MODE='basic'
		return 0
	fi

	if [[ -n ${KIBANA_API_KEY:-} ]]; then
		if [[ ! ${KIBANA_API_KEY} =~ ^[A-Za-z0-9_+/=-]+$ ]]; then
			echo 'KIBANA_API_KEY doit contenir une clé API Kibana valide.' >&2
			return 1
		fi
		if [[ ${purpose} == 'rules' && ${OPENIRN_RULES_ALLOW_API_KEY:-false} != true ]]; then
			cat >&2 <<-'EOF'
				Les règles d'alerte ne peuvent pas être déployées avec KIBANA_API_KEY :
				Kibana exécuterait chaque règle avec cette clé, et toutes les règles
				échoueraient (security_exception) dès son expiration ou son invalidation.
				Utiliser KIBANA_USERNAME et KIBANA_PASSWORD, Kibana crée alors pour chaque
				règle une clé API dédiée, sans expiration, indépendante de la session.
				Pour une clé API sans expiration réservée aux règles, définir
				OPENIRN_RULES_ALLOW_API_KEY=true.
			EOF
			return 1
		fi
		(umask 077; printf 'header = "Authorization: ApiKey %s"\n' "${KIBANA_API_KEY}" > "${output}")
		KIBANA_AUTH_MODE='api_key'
		return 0
	fi

	echo 'Définir KIBANA_USERNAME et KIBANA_PASSWORD, ou KIBANA_API_KEY.' >&2
	return 1
}
