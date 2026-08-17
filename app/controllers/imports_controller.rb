require "csv"
require "roo"
require "caxlsx"

class ImportsController < ApplicationController
  before_action :require_admin_or_gerente!

  def new
    @project_types = ProjectType.all
    @project_type = ProjectType.find_by(id: params[:project_type_id])
  end

  def template
    project_type = ProjectType.find(params[:project_type_id])
    if params[:format] == "xlsx"
      send_data xlsx_template_for(project_type), filename: "plantilla-#{project_type.slug}.xlsx",
        type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    else
      send_data csv_template_for(project_type), filename: "plantilla-#{project_type.slug}.csv", type: "text/csv"
    end
  end

  def preview
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    @preview = build_preview(@project_type, params[:file])
    render :new
  end

  def create
    @project_type = ProjectType.find(params[:project_type_id])
    @project_types = ProjectType.all
    valid_rows = begin
      JSON.parse(params[:valid_rows] || "[]")
    rescue JSON::ParserError
      []
    end
    @results = commit_rows(@project_type, valid_rows)
    render :new
  end

  private

  def commit_rows(project_type, valid_rows)
    created = 0
    row_errors = []

    valid_rows.each do |row|
      project = Project.new(project_type: project_type, name: row["name"], custom_fields: row["custom_fields"] || {})
      if project.save
        ProjectAccess.create!(user: current_user, project: project, can_edit: true) if current_user.gerente?
        created += 1
      else
        row_errors << { row: row["row"], message: project.errors.full_messages.join(", ") }
      end
    end

    { created: created, errors: row_errors }
  end

  def csv_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    CSV.generate do |csv|
      csv << ["Nombre"] + fields.map(&:label)
    end
  end

  def xlsx_template_for(project_type)
    fields = project_type.field_definitions.order(:position)
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: project_type.name.truncate(31)) do |sheet|
      sheet.add_row ["Nombre"] + fields.map(&:label)
    end
    package.to_stream.read
  end

  def build_preview(project_type, file)
    fields = project_type.field_definitions.order(:position).to_a
    return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "No se subió ningún archivo" }], valid_rows_json: "[]", fields: fields } if file.blank?

    parsed_rows = begin
      parse_rows(file, fields)
    rescue ArgumentError
      return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "Formato no soportado, subí un .csv o .xlsx" }], valid_rows_json: "[]", fields: fields }
    rescue StandardError
      return { rows: [{ row: 0, name: nil, custom_fields: {}, error: "No se pudo leer el archivo" }], valid_rows_json: "[]", fields: fields }
    end
    rows = []
    valid_rows = []

    parsed_rows.each_with_index do |(name, custom_fields), index|
      row_number = index + 2
      project = Project.new(project_type: project_type, name: name, custom_fields: custom_fields)
      if project.valid?
        rows << { row: row_number, name: name, custom_fields: custom_fields, error: nil }
        valid_rows << { row: row_number, name: name, custom_fields: custom_fields }
      else
        rows << { row: row_number, name: name, custom_fields: custom_fields, error: project.errors.full_messages.join(", ") }
      end
    end

    { rows: rows, valid_rows_json: valid_rows.to_json, fields: fields }
  end

  def parse_rows(file, fields)
    extension = File.extname(file.original_filename).downcase

    case extension
    when ".csv"
      csv = CSV.parse(file.read.force_encoding("UTF-8").sub("﻿", ""), headers: true)
      header_map = header_map_for(csv.headers)
      csv.map { |row| extract_row(row.to_h, header_map, fields) }
    when ".xlsx"
      sheet = Roo::Spreadsheet.open(file.path, extension: extension.delete(".").to_sym).sheet(0)
      raw_headers = sheet.row(1)
      header_map = header_map_for(raw_headers)
      (2..sheet.last_row).map { |i| extract_row(raw_headers.zip(sheet.row(i)).to_h, header_map, fields) }
    else
      raise ArgumentError, "unsupported extension"
    end
  end

  # Matches file headers to "Nombre"/field labels ignoring case and surrounding spaces,
  # so "nombre ", "NOMBRE" or " Cliente " line up with the plantilla's exact labels.
  def header_map_for(headers)
    headers.each_with_object({}) { |h, map| map[h.to_s.strip.downcase] = h }
  end

  def extract_row(raw_row, header_map, fields)
    name_header = header_map[normalize_header("Nombre")]
    custom_fields = fields.each_with_object({}) do |f, h|
      value_header = header_map[normalize_header(f.label)]
      h[f.key] = resolve_field_value(f, value_header ? raw_row[value_header] : nil)
    end
    [name_header ? raw_row[name_header] : nil, custom_fields]
  end

  def normalize_header(value)
    value.to_s.strip.downcase
  end

  NUMERIC_FIELD_TYPES = %w[number currency percent].freeze

  def resolve_field_value(field, raw_value)
    return raw_value if raw_value.blank?

    if field.data_type == "reference"
      record = field.reference_table.classify.constantize.find_by(name: raw_value.to_s.strip)
      record ? record.id : "#{raw_value} (no encontrado)"
    elsif NUMERIC_FIELD_TYPES.include?(field.data_type)
      normalize_number(raw_value)
    else
      raw_value
    end
  end

  # Excel exports numbers with currency symbols ("₡1.234,56") or a comma decimal
  # separator ("12,50") that Float() rejects outright - strip symbols and pick the
  # rightmost of "," / "." as the decimal separator, discarding the other as a
  # thousands separator.
  def normalize_number(raw_value)
    cleaned = raw_value.to_s.strip.gsub(/[^\d,.\-]/, "")
    return raw_value if cleaned.blank?

    last_comma = cleaned.rindex(",")
    last_dot = cleaned.rindex(".")
    if last_comma && last_dot
      decimal, thousands = last_comma > last_dot ? [",", "."] : [".", ","]
      cleaned = cleaned.delete(thousands).sub(decimal, ".")
    elsif last_comma
      cleaned = cleaned.tr(",", ".")
    end
    cleaned
  end
end
