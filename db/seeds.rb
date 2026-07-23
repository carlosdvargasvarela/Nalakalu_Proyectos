instalaciones = ProjectType.find_or_create_by!(slug: "instalaciones") do |pt|
  pt.name = "Instalaciones"
end

[
  { key: "proyecto", label: "Proyecto", data_type: "text", position: 1, show_in_gantt: true },
  { key: "cliente", label: "Cliente", data_type: "text", position: 2, show_in_gantt: true },
  { key: "vendedor", label: "Vendedor", data_type: "text", position: 3, show_in_gantt: false },
  { key: "direccion", label: "Dirección", data_type: "text", position: 4, show_in_gantt: false },
  { key: "contacto", label: "Contacto", data_type: "text", position: 5, show_in_gantt: false },
  { key: "instalador", label: "Instalador", data_type: "reference", reference_table: "installers", position: 6, show_in_gantt: true }
].each do |attrs|
  instalaciones.field_definitions.find_or_create_by!(key: attrs[:key]) { |f| f.assign_attributes(attrs) }
end

["Diseño-Aprobación", "Revisión Inicial", "Producción", "Entrega", "Instalación"].each_with_index do |name, index|
  instalaciones.stage_templates.find_or_create_by!(name: name) { |s| s.position = index + 1 }
end
