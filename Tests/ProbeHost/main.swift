// Links TrustMe (and so the TrustMeProbe constructor). Run normally it prints
// a marker; run with TRUSTME_TCC_PROBE set, the constructor answers first and
// this line never runs.
import TrustMe

_ = Permission.accessibility.id
print("probe host started normally")
