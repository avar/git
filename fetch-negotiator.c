#include "git-compat-util.h"
#include "fetch-negotiator.h"
#include "negotiator/default.h"
#include "negotiator/skipping.h"
#include "negotiator/noop.h"
#include "repository.h"

void fetch_negotiator_init(struct repository *r,
			   struct fetch_negotiator *negotiator)
{
	enum fetch_negotiation_setting setting;
	prepare_repo_settings(r);
	setting = r->settings.fetch_negotiation_algorithm;

	switch (setting) {
	case FETCH_NEGOTIATION_SKIPPING:
		skipping_negotiator_init(negotiator);
		return;

	case FETCH_NEGOTIATION_NOOP:
		noop_negotiator_init(negotiator);
		return;

	case FETCH_NEGOTIATION_DEFAULT:
		default_negotiator_init(negotiator);
		return;
	}
}
