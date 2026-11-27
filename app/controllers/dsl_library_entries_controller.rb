class DslLibraryEntriesController < ApplicationController
  before_action :set_entry, only: [:edit, :update]

  def index
    @entries = DslLibraryEntry.order(:name).paginate(page: params[:page].to_i.clamp(1, 100_000), per_page: 100)
    begin
      @self_url = Dsl::Support::UrlPlaceholders.expand(Dsl::Support::UrlPlaceholders::TOKEN)
    rescue ArgumentError => error
      @self_url_error = error.message
    end
  end

  def new
    @entry = DslLibraryEntry.new
    render :edit
  end

  def create
    @entry = DslLibraryEntry.new(entry_params.except(:lock_version))
    if @entry.save
      redirect_to edit_dsl_library_entry_path(@entry), notice: "Library instruction created."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @entry.update(entry_params)
      redirect_to edit_dsl_library_entry_path(@entry), notice: "Library instruction saved. Renamed references were updated together; changes apply on the next execution."
    else
      render :edit, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => error
    @entry.reload
    @entry.errors.add(:base, "No changes saved: the rename or reference update failed (#{error.class.name}). Review the name and referencing entries.")
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::StaleObjectError
    @entry.reload
    @entry.errors.add(:base, "Another operator saved this entry. Review the current version before editing again.")
    render :edit, status: :conflict
  end

  private
  def set_entry
    @entry = DslLibraryEntry.find(params[:id])
  end
  def entry_params
    params.require(:dsl_library_entry).permit(:name, :body, :description, :lock_version)
  end
end
