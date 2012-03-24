// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
  BEGIN LICENSE

  Copyright (C) 2011-2012 Mario Guerriero <mefrio.g@gmail.com>
  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as
  published    by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program.  If not, see <http://www.gnu.org/licenses>

  END LICENSE
***/

using Gtk;
using Gdk;
using Gst;
using Granite.Widgets;

using Resources;

namespace Snap.Widgets {

    public class MediaViewer : Granite.Widgets.StaticNotebook {
        
        public int photos;
        public int videos;
        
        private MediaViewerPage all_viewer;
        private MediaViewerPage photo_viewer;
        private MediaViewerPage video_viewer;
        
        public signal void selection_changed (string path, MediaType media_type);
        
        public MediaViewer () {

            all_viewer = new MediaViewerPage (this, null);
            photo_viewer = new MediaViewerPage (this, MediaType.PHOTO);
            video_viewer = new MediaViewerPage (this, MediaType.VIDEO);
            
            photos = photo_viewer.counter;
            videos = video_viewer.counter;
            
            append_page (all_viewer, new Label (_("All")));
            append_page (photo_viewer, new Label (_("Photo")));
            append_page (video_viewer, new Label (_("Video")));
        
            show_all ();
        }

        /**
         * Updates the list of elements
         *
         * @param media_type type of media-view to update. Passing NULL updates everything [allow-none]. 
         */
        public void update_items (MediaType? media_type = null) {
            debug ("Updating MediaViewer items");
            if (media_type == null)
                all_viewer.update_items ();
            else if (media_type == MediaType.PHOTO)
                photo_viewer.update_items ();
            else if (media_type == MediaType.VIDEO)
                video_viewer.update_items ();
        }
        
    }

    private class MediaViewerPage : ScrolledWindow {

        /* TODO:
           - update_items medias automatically
           - Add context menu options ('delete' and 'trash file')
           - Use a hasmap as model (get rid of ListStore)
        */

        //Gnome.DesktopThumbnailFactory thumbnail_factory;

        public string selected {get; private set;}
        
        MediaViewer parent;
        private MediaType? media_type;
        public int counter = 0;
        
        private Gee.HashMap<string, int> items_map;

        private ListStore store;
        private IconView icon_view;

        public MediaViewerPage (MediaViewer parent, MediaType? media_type = null) {
            this.parent = parent;
            this.media_type = media_type;
            //this.thumbnail_factory = new Gnome.DesktopThumbnailFactory (Gnome.ThumbnailSize.NORMAL);

            items_map = new Gee.HashMap<string, int> ();
            store = new Gtk.ListStore (2, typeof (Gdk.Pixbuf), typeof (string));

            icon_view = new Gtk.IconView ();

            var icon_view_style = new Gtk.CssProvider ();
            try {
                icon_view_style.load_from_data (Resources.ICON_VIEW_STYLESHEET, -1);
            } catch (Error e) {
                warning (e.message);
            }

            icon_view.get_style_context ().add_class ("snap-icon-view");
            icon_view.get_style_context ().add_provider (icon_view_style, STYLE_PROVIDER_PRIORITY_THEME);

            icon_view.set_columns (0);
            icon_view.set_selection_mode (Gtk.SelectionMode.SINGLE);
            icon_view.set_pixbuf_column (0);
            icon_view.set_tooltip_column (1);
            icon_view.set_model (store);

            icon_view.margin = 0;
            icon_view.column_spacing = 6;

            icon_view.selection_changed.connect (on_selection_changed);

            update_items ();

            this.vscrollbar_policy = PolicyType.NEVER;
            this.add (icon_view);
        }

        // FIXME: this needs serious performance improvements. See list_files() as well
        public void update_items () {
            if (media_type == null)
                return;

            list_dir ();
        }

        private void on_selection_changed () {
            var item = icon_view.get_selected_items ();
            if (item != null) {
                string background;
                TreeIter iter;

                store.get_iter_from_string(out iter, item.nth_data (0).to_string());
                store.get (iter, 1, out background);

                var path = GLib.File.new_for_path(background).get_path();
                this.selected = path;
                parent.selection_changed (path, media_type);
            }
        }

        /**
         * Function used to scan the media folder
         **/
        private void list_dir () {
            debug ("Start scan\n");
            var dir = File.new_for_path (get_media_dir (media_type));
            // asynchronous call, with callback, to get dir entries
            dir.enumerate_children_async (FILE_ATTRIBUTE_STANDARD_NAME, 0,
                                            Priority.DEFAULT, null, list_ready);
        }

        /* Callback for enumerate_children_async */
        private void list_ready (GLib.Object? file, AsyncResult res) {
            try {
                FileEnumerator e = ((File) file).enumerate_children_async.end (res);
                // asynchronous call, with callback, to get entries so far
                e.next_files_async (10, Priority.DEFAULT, null, list_files);
            } catch (Error err) {
                warning ("Error async_ready failed %s\n", err.message);
            }

        }

        // FIXME: Improve performance. We'll also need to unset() values from the hasmap
        // when we implement the delete feature.
        /* Callback for next_files_async */
        private void list_files (GLib.Object? sender, AsyncResult res) {
            Gtk.TreeIter iter;
            try {
                var enumer = (FileEnumerator) sender;

                // get a list of the files found so far
                GLib.List<FileInfo> list = enumer.next_files_async.end (res);

                foreach (FileInfo info in list) {
                    string filename = build_media_filename (info.get_name (), media_type);
                    warning (filename);
                    if (items_map.has_key (filename))
                        continue;

                    items_map.set (filename, 0);

                    icon_view.set_columns (icon_view.columns + 1);
                    
                    this.store.append (out iter);

                    Gdk.Pixbuf? pix = null;

                    // Render image and add shadow
                    if (media_type == MediaType.PHOTO)
                        pix = get_pixbuf_shadow (new Gdk.Pixbuf.from_file_at_size (filename, 100, 150), 0);
                    else
                        pix = MEDIA_VIDEO_ICON.render (null, null, 64);

                    this.store.set (iter, 0, pix, 1, filename);
                    counter++;
                }

                // asynchronous call, with callback, to get any more entries
                enumer.next_files_async (10, Priority.DEFAULT, null, list_files);
            } catch (Error err) {
                warning ("error list_files failed %s\n", err.message);
            }
        }
    }
}
