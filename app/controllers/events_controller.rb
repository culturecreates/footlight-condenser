class EventsController < ApplicationController

  # GET /websites/:seedurl/events
  def index
    @events = []
    event_rdfs_class_id = RdfsClass.where(name:"Event")

    titles = Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Title", rdfs_class: 1}, websites:  {seedurl: params[:seedurl]}, webpages: {archive_date: Time.now.midnight..Time.now.next_year}  }  }  ).pluck(:rdf_uri,:cache, "sources.language")
    titles_hash = titles.map {|title| [title[0],title[1]] if !title[1].blank? }.to_h
    photos_hash = Statement.joins({source: [:property, :website]},:webpage).where({sources:{selected: true, properties:{label: "Photo", rdfs_class: 1},websites:  {seedurl:  params[:seedurl]},webpages: {archive_date: Time.now.midnight..Time.now.next_year}   }  }  ).order(:created_at).pluck(:rdf_uri, :cache).to_h

    uris_with_problems = Statement.joins({webpage: :website},:source).where(webpages:{websites: {seedurl: params[:seedurl]}}).where(sources: {selected: true}).where(status: "problem").pluck(:rdf_uri).uniq
    uris_to_review = Statement.joins({webpage: :website},:source).where(webpages:{websites: {seedurl: params[:seedurl]}}).where(sources: {selected: true}).where(status: "initial").pluck(:rdf_uri).uniq
    uris_updated = Statement.joins({webpage: :website},:source).where(webpages:{websites: {seedurl: params[:seedurl]}}).where(sources: {selected: true}).where(status: "updated").pluck(:rdf_uri).uniq

    photos_hash.each do |photo|
        @events << {rdf_uri: photo[0], statements_status: {to_review: uris_to_review.include?(photo[0]), updated: uris_updated.include?(photo[0]), problem: uris_with_problems.include?(photo[0])}, photo: photo[1], title: titles_hash[photo[0]]  }
    end
    @total_events = @events.count
  end

end
