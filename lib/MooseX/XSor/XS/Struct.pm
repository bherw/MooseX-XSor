package MooseX::XSor::XS::Struct;

use Moose ();
use Moose::Exporter;

Moose::Exporter->setup_import_methods(
	class_metaroles => {
		attribute   => ['MooseX::XSor::XS::Meta::Attribute'],
		class       => ['MooseX::XSor::XS::Meta::Class'],
		constructor => ['MooseX::XSor::XS::Meta::Method::Constructor'],
		instance    => ['MooseX::XSor::XS::Meta::Instance::Struct'],
	},
	also => ['Moose'],
);

1;
