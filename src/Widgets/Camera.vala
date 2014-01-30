// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
  BEGIN LICENSE
 
  Copyright (C) 2013 Mario Guerriero <mario@elementaryos.org>
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

namespace Snap.Widgets {
 
    public class Camera : Gtk.DrawingArea {
        
        public enum ActionType {
            PHOTO = 0,
            VIDEO;
        }       
                
        public static const int WIDTH = 640;
        public static const int HEIGHT = 480;
        
        private ActionType type;
        
        private bool capturing = false;
        
        private Gst.Element? camerabin = null;
        private Gst.Element? videoflip = null;
        
        public signal void capture_start ();
        public signal void capture_end ();
        
        public class Camera () {
            this.set_size_request (WIDTH, HEIGHT); // FIXME

            this.videoflip = Gst.ElementFactory.make ("videoflip", "videoflip");
            this.videoflip.set_property("method", 4);

            this.camerabin = Gst.ElementFactory.make ("camerabin","camera");
            this.camerabin.set_property("viewfinder-filter", videoflip);
            this.camerabin.bus.add_watch (0,(bus,message) => {
                if (Gst.Video.is_video_overlay_prepare_window_handle_message (message))
                    (message.src as Gst.Video.Overlay).set_window_handle ((uint*) Gdk.X11Window.get_xid (this.get_window()));
                return true;
            });
            
            var preview_caps = Gst.Caps.from_string ("video/x-raw, format=\"rgb\", width = (int) %d, height = (int) %d".printf (WIDTH, HEIGHT));
            this.camerabin.set ("preview-caps", preview_caps);
            
            // Workaround to fix a CSD releated bug.
            // See https://bugzilla.gnome.org/show_bug.cgi?id=721148
            // for more information
            Gdk.Visual visual = Gdk.Visual.get_system ();
            if (visual != null)
                this.set_visual (visual);
            // workaround END
            
            this.show_all ();
            this.play ();
        }
        
        /**
         * Change the camera recording type (switch between Video or Photo mode)
         */
        public void set_action_type (ActionType type) {
            this.type = type;
        }
       
        /**
         * Starts Camera visualization
         */
        public void play () {
            this.camerabin.set_state (Gst.State.PLAYING);  
        }
       
        /**
         * Stops Camera visualization
         */
        public void stop () {
            this.camerabin.set_state (Gst.State.NULL);  
        }
        
        /**
         * Send to the Camera an acquire signal depending on its recording mode
         */
        public void take_start () {
            debug ("Recording...");
            
            this.capture_start ();
            
            string location = Resources.get_new_media_filename (this.type);
            
            // "(int) this.type + 1" is here because GST developers used mode 1 for photos
            // and mode 2 for videos (can't understand why not 0 and 1)
            this.camerabin.set_property ("mode", (int) this.type + 1);
            
            this.capturing = (this.type == ActionType.VIDEO);
            
            debug ("%s", location);

            camerabin.set_property ("location", location);
            GLib.Signal.emit_by_name (camerabin, "start-capture");
        
            if (this.type == ActionType.PHOTO)
                this.capture_end ();
        }
        
        /**
         * Tells the camera to stop recording (to be used only in video mode)
         */
        public void take_stop () {
            debug ("Stopping video record...");
            
            this.capturing = false;
            
            GLib.Signal.emit_by_name (camerabin, "stop-capture");
            
            this.capture_end ();
        }
        
        /**
         * @return true if camera is recording a video, false otherwise
         */
        public bool get_capturing () {
            return capturing;
        }
        
    }
}
