enum Status { ok, pending }

String statusB() => '${Status.pending} ${Status.ok.name}';
