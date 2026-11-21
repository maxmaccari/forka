# Require documentation and typespecs throughout the domain layer.
%Doctor.Config{
  ignore_modules: [Forka.Application, Forka.Mailer, Forka.Repo],
  ignore_paths: [~r{^lib/forka_web}, ~r{^test/}],
  min_module_doc_coverage: 100,
  min_module_spec_coverage: 100,
  min_overall_doc_coverage: 0,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Full,
  struct_type_spec_required: true,
  umbrella: false
}
